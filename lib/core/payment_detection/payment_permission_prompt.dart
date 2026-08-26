import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/receipt_sheet_widgets.dart';
import '../bootstrap/app_prefs.dart';
import '../theme/receipt_sheet_theme.dart';
import 'payment_event_bridge.dart';

/// Setup walkthrough for the two payment-detection permissions that have no
/// system runtime dialog (unlike POST_NOTIFICATIONS / location).
///
/// Android only allows these via a Settings toggle, so this shows an in-app
/// rationale then opens that toggle — the same pattern as "Allow" for
/// notifications, just one extra tap. No-ops on iOS/web.
///
/// Triggered:
/// - Automatically once per install when the user first enters [MainShell]
///   after login (`maybeRunOnAppEnter`), if payment detection is on and any
///   permission is still missing.
/// - Manually when the user turns on Profile → "Payment detection"
///   (`runSetupWalkthrough`), regardless of the once-per-install flag.
///
/// Walks notification access, then overlay, prompting for whichever is still
/// missing. After opening a Settings screen it waits for the app to resume
/// before continuing to the next step.
abstract final class PaymentPermissionPrompt {
  static bool _inFlight = false;
  static Completer<void>? _resumeCompleter;

  /// Pure gate for the once-per-install auto-prompt. No I/O — callers supply
  /// the current platform / prefs / permission snapshot.
  static bool shouldAutoPrompt({
    required bool isAndroid,
    required bool promptAlreadyDone,
    required bool paymentDetectionEnabled,
    required bool notificationAccessGranted,
    required bool overlayPermissionGranted,
  }) {
    if (!isAndroid) return false;
    if (promptAlreadyDone) return false;
    if (!paymentDetectionEnabled) return false;
    if (notificationAccessGranted && overlayPermissionGranted) return false;
    return true;
  }

  /// Once-per-install auto walkthrough. Call from [MainShell] after the first
  /// frame. Marks the prompt done whether the user grants, declines, or both
  /// permissions were already present when checked.
  static Future<void> maybeRunOnAppEnter(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (AppPrefs.paymentPermissionPromptDone) return;

    final detectionEnabled =
        await PaymentEventBridge.isPaymentDetectionEnabled();
    final notificationGranted =
        await PaymentEventBridge.isNotificationAccessGranted();
    final overlayGranted =
        await PaymentEventBridge.isOverlayPermissionGranted();

    final shouldPrompt = shouldAutoPrompt(
      isAndroid: true,
      promptAlreadyDone: AppPrefs.paymentPermissionPromptDone,
      paymentDetectionEnabled: detectionEnabled,
      notificationAccessGranted: notificationGranted,
      overlayPermissionGranted: overlayGranted,
    );

    if (!shouldPrompt) {
      // Both already granted (or detection off) — never ask again this install.
      await AppPrefs.setPaymentPermissionPromptDone();
      return;
    }

    if (!context.mounted) return;
    await runSetupWalkthrough(context);
    await AppPrefs.setPaymentPermissionPromptDone();
  }

  /// Runs the permission walkthrough. Call after enabling payment detection
  /// from Settings, or from [maybeRunOnAppEnter].
  static Future<void> runSetupWalkthrough(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      final openedNotificationSettings =
          await _promptNotificationAccess(context);
      if (!context.mounted) return;
      if (openedNotificationSettings) {
        await _waitForResume();
        if (!context.mounted) return;
      }
      final openedOverlaySettings = await _promptOverlay(context);
      if (!context.mounted) return;
      if (openedOverlaySettings) {
        await _waitForResume();
      }
    } finally {
      _inFlight = false;
    }
  }

  /// Returns true when a system Settings screen was opened.
  static Future<bool> _promptNotificationAccess(BuildContext context) async {
    if (await PaymentEventBridge.isNotificationAccessGranted()) return false;
    if (!context.mounted) return false;

    final allow = await _showRationale(
      context,
      icon: '🔔',
      title: 'Allow notification access',
      body:
          "Receipt Drop can automatically save your spending by reading "
          "payment notifications from apps like Maybank, Touch 'n Go, and "
          "Google Wallet. Android will open the settings screen next — "
          "just turn on Receipt Drop.",
    );
    if (allow == true) {
      await PaymentEventBridge.openNotificationAccessSettings();
      return true;
    }
    return false;
  }

  /// Returns true when a system Settings screen was opened.
  static Future<bool> _promptOverlay(BuildContext context) async {
    if (await PaymentEventBridge.isOverlayPermissionGranted()) return false;
    if (!context.mounted) return false;

    final allow = await _showRationale(
      context,
      icon: '🪟',
      title: 'Allow display over other apps',
      body:
          'Shows a small category picker on top of your banking app after a '
          'payment, without opening Receipt Drop. Android will open a '
          'settings screen — turn on Receipt Drop.',
    );
    if (allow == true) {
      await PaymentEventBridge.openOverlayPermissionSettings();
      return true;
    }
    return false;
  }

  /// Pauses the walk until the app returns from a system Settings screen.
  static Future<void> _waitForResume() async {
    if (_resumeCompleter != null) return _resumeCompleter!.future;
    final completer = Completer<void>();
    _resumeCompleter = completer;

    final binding = WidgetsBinding.instance;
    late final _LifecycleObserver observer;
    observer = _LifecycleObserver((state) {
      if (state == AppLifecycleState.resumed && !completer.isCompleted) {
        completer.complete();
      }
    });
    binding.addObserver(observer);
    try {
      // Already resumed (e.g. Settings opened and closed instantly, or
      // platform quirk) — don't hang forever.
      if (binding.lifecycleState == AppLifecycleState.resumed) {
        // Give the pause a chance to flip to inactive/paused first.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (binding.lifecycleState == AppLifecycleState.resumed &&
            !completer.isCompleted) {
          completer.complete();
        }
      }
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {},
      );
    } finally {
      binding.removeObserver(observer);
      _resumeCompleter = null;
    }
  }

  static Future<bool?> _showRationale(
    BuildContext context, {
    required String icon,
    required String title,
    required String body,
  }) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: const Color(0x80231F1A),
      builder: (ctx) => _RationaleDialog(icon: icon, title: title, body: body),
    );
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._onState);

  final void Function(AppLifecycleState state) _onState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onState(state);
}

/// The gold-badge / cream-card rationale dialog shared by both
/// [PaymentPermissionPrompt] prompts — reuses the receipt-flow sheets' gold
/// + cream + Baloo 2 mini design system ([ReceiptSheetColors], [balooText],
/// [ReceiptSheetCta], [ReceiptSheetLink]) rather than introducing a new,
/// near-duplicate palette for this one dialog.
class _RationaleDialog extends StatelessWidget {
  const _RationaleDialog({
    required this.icon,
    required this.title,
    required this.body,
  });

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReceiptSheetColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: ReceiptSheetColors.gold,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: ReceiptSheetColors.ctaShadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: balooText(
                21,
                FontWeight.w800,
                color: ReceiptSheetColors.heading,
                letterSpacing: -0.3,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: balooText(
                14,
                FontWeight.w500,
                color: ReceiptSheetColors.body,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            ReceiptSheetCta(
              label: 'Continue  ›',
              onPressed: () => Navigator.pop(context, true),
            ),
            ReceiptSheetLink(
              label: 'Not now',
              color: ReceiptSheetColors.sub,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}
