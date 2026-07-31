import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/pending_imports_repository.dart';
import '../routing/app_router.dart';

const _androidChannelId = 'receipt_saved';
const _androidChannelName = 'Receipt saved';
const _androidChannelDescription =
    'Acknowledges a receipt shared into Receipt Drop and lets you add a note.';
const _noteActionId = 'add_note';
const _darwinCategoryId = 'receipt_note_reply';

/// Fixed ID for the grouped multi-file-share notification — distinct from
/// any single-receipt notification's derived ID (see [_stableNotificationId]),
/// which is always non-negative.
const _batchNotificationId = -1;

/// Local (on-device) interactive notification for the post-share receipt
/// flow — acknowledges a shared receipt and lets the user attach a note
/// without opening the app. See
/// `docs/plans/2026-07-30-post-share-receipt-notification.md`.
///
/// Every public method is best-effort: a missing permission, an
/// uninitialized plugin, or a platform quirk must never block saving or
/// processing the underlying receipt, so failures are swallowed here rather
/// than surfaced to callers.
abstract final class ReceiptNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwinInit = DarwinInitializationSettings(
        notificationCategories: [
          DarwinNotificationCategory(
            _darwinCategoryId,
            actions: [
              // No `foreground` option: this is what keeps the action from
              // launching the app on submit (best-effort — see the
              // termination-state caveat on _handleBackgroundResponse).
              DarwinNotificationAction.text(
                _noteActionId,
                'Update',
                buttonTitle: 'Update',
                placeholder: 'Dinner with friends',
              ),
            ],
          ),
        ],
      );

      await _plugin.initialize(
        InitializationSettings(android: androidInit, iOS: darwinInit),
        onDidReceiveNotificationResponse: _handleForegroundResponse,
        onDidReceiveBackgroundNotificationResponse:
            _handleBackgroundResponse,
      );

      const channel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDescription,
        importance: Importance.low,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await _requestPermissions();
      _initialized = true;
    } on Object catch (e) {
      debugPrint('ReceiptNotificationService.init: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } on Object catch (e) {
      // Denied/unavailable permission falls back to the existing in-app
      // toast (see ShareIntentListener) — never a crash, never a re-prompt
      // beyond the single OS-native dialogue.
      debugPrint('ReceiptNotificationService._requestPermissions: $e');
    }
  }

  /// Posts the single-receipt interactive notification: "Receipt saved" +
  /// (if known) the source app, with an inline "Add a note"/Update action.
  /// Notification ID is derived from [pendingImportId] so a later call with
  /// the same ID updates this notification in place rather than stacking.
  static Future<void> showReceiptSaved({
    required String pendingImportId,
    String? sourceApp,
  }) async {
    if (!_initialized) return;
    try {
      final body = sourceApp != null
          ? '$sourceApp receipt is processing'
          : 'Your receipt is processing';
      await _plugin.show(
        _stableNotificationId(pendingImportId),
        '🧾 Receipt saved',
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
            actions: [
              AndroidNotificationAction(
                _noteActionId,
                'Update',
                // Keeps this the one interaction that never opens the app —
                // handled by _handleBackgroundResponse in its own isolate.
                showsUserInterface: false,
                inputs: [
                  AndroidNotificationActionInput(label: 'Add a note'),
                ],
              ),
            ],
          ),
          iOS: DarwinNotificationDetails(categoryIdentifier: _darwinCategoryId),
        ),
        payload: pendingImportId,
      );
    } on Object catch (e) {
      debugPrint('ReceiptNotificationService.showReceiptSaved: $e');
    }
  }

  /// Posts one grouped notification for a multi-file share — deliberately
  /// no per-file note action (see Decision Logic in the linked plan doc).
  /// Tapping it opens Pending Imports, same as tapping any single-receipt
  /// notification's body.
  static Future<void> showBatchSaved({required int count}) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        _batchNotificationId,
        '🧾 Receipts saved',
        '$count receipts saved — processing',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.low,
            priority: Priority.low,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } on Object catch (e) {
      debugPrint('ReceiptNotificationService.showBatchSaved: $e');
    }
  }

  /// Deterministic, positive notification ID so the same [pendingImportId]
  /// always maps to the same ID (String.hashCode isn't a documented-stable
  /// contract to build a notification key on).
  static int _stableNotificationId(String id) {
    var hash = 7;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash;
  }
}

/// Handles the note-reply action while the app process is alive (foreground
/// or backgrounded-but-not-killed) and, separately, a plain tap on the
/// notification body — which on Android/iOS already launched/foregrounded
/// the app through the normal OS mechanism by the time this fires, so it's
/// safe to navigate here.
Future<void> _handleForegroundResponse(NotificationResponse response) async {
  if (response.actionId == _noteActionId) {
    await _writeNote(response);
    return;
  }
  _openPendingImports();
}

/// Background-isolate entry point (Android only): fired when the note-reply
/// action is submitted while Receipt Drop's process is not running. Must
/// stay minimal — no full app bootstrap, just enough to persist the note.
///
/// iOS does not deliver text-input notification actions through an
/// equivalent background isolate mechanism when the app is terminated; this
/// callback effectively only ever fires on Android. See Edge
/// Cases/Tradeoffs in `docs/plans/2026-07-30-post-share-receipt-notification.md`
/// — full "works even when force-quit" reliability on iOS is an open
/// question flagged there, not assumed solved by this code.
@pragma('vm:entry-point')
void _handleBackgroundResponse(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  if (response.actionId == _noteActionId) {
    // Fire-and-forget: nothing meaningful to await from inside a plugin
    // callback the OS doesn't otherwise wait on.
    unawaited(_writeNote(response));
  }
}

Future<void> _writeNote(NotificationResponse response) async {
  final pendingImportId = response.payload;
  final text = response.input;
  if (pendingImportId == null || text == null || text.trim().isEmpty) return;

  final db = AppDatabase();
  try {
    await PendingImportsRepository(db).setNote(pendingImportId, text);
  } on Object catch (e) {
    debugPrint('ReceiptNotificationService._writeNote: $e');
  } finally {
    await db.close();
  }
}

void _openPendingImports() {
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  context.pushNamed('pending-imports');
}
