import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A payment event captured natively (payment notification detected) and
/// durably queued on the Android side, waiting for Flutter to save it as a
/// real transaction.
/// See android/app/src/main/kotlin/.../paymentdetect/PaymentEventQueueStore.kt.
class QueuedPaymentEvent {
  const QueuedPaymentEvent({
    required this.id,
    required this.merchantRaw,
    required this.amountMyr,
    required this.category,
    required this.suggestedCategory,
    required this.sourcePackage,
    required this.occurredAt,
    required this.fingerprint,
  });

  factory QueuedPaymentEvent.fromMap(Map<Object?, Object?> map) {
    return QueuedPaymentEvent(
      id: map['id'] as String,
      merchantRaw: map['merchantRaw'] as String,
      amountMyr: (map['amountMyr'] as num).toDouble(),
      category: map['category'] as String?,
      suggestedCategory: map['suggestedCategory'] as String?,
      sourcePackage: map['sourcePackage'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        map['occurredAtEpochMs'] as int,
      ),
      fingerprint: map['fingerprint'] as String,
    );
  }

  final String id;
  final String merchantRaw;
  final double amountMyr;

  /// The category the user tapped on the floating overlay. Null when the
  /// overlay was never shown — a notification the OS delivered too late to
  /// interrupt the user over (see [suggestedCategory]).
  final String? category;

  /// Native [CategoryMatcher]'s guess, carried so an uncategorized event
  /// still lands on a sensible default when it goes to the review queue.
  final String? suggestedCategory;

  final String sourcePackage;
  final DateTime occurredAt;
  final String fingerprint;

  /// True when no one has confirmed a category for this event yet, so it must
  /// reach the user as a review-queue item rather than a settled transaction.
  bool get needsReview => category == null;
}

/// Whether payment detection is permitted *and* actually running.
///
/// [granted] and [active] come apart on OEM skins (MIUI/HyperOS especially)
/// that require a separate "background autostart" allowance before the OS
/// will bind a notification listener: system Settings keeps reporting
/// notification access as allowed while the listener is never started, so
/// the feature silently receives nothing. Surfacing [PaymentListenerState
/// .grantedButInactive] is the difference between a user seeing a fixable
/// warning and the feature just appearing broken.
enum PaymentListenerState { notGranted, grantedButInactive, active }

class PaymentListenerStatus {
  const PaymentListenerStatus({
    required this.granted,
    required this.active,
    required this.neverConnected,
    this.lastNotificationAt,
  });

  const PaymentListenerStatus.unavailable()
    : granted = false,
      active = false,
      neverConnected = true,
      lastNotificationAt = null;

  factory PaymentListenerStatus.fromMap(Map<Object?, Object?> map) {
    final lastNotificationMs = (map['lastNotificationAtEpochMs'] as int?) ?? 0;
    return PaymentListenerStatus(
      granted: (map['enabled'] as bool?) ?? false,
      active: (map['connected'] as bool?) ?? false,
      neverConnected: (map['neverConnected'] as bool?) ?? true,
      lastNotificationAt: lastNotificationMs == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastNotificationMs),
    );
  }

  final bool granted;
  final bool active;
  final bool neverConnected;
  final DateTime? lastNotificationAt;

  PaymentListenerState get state {
    if (!granted) return PaymentListenerState.notGranted;
    return active
        ? PaymentListenerState.active
        : PaymentListenerState.grantedButInactive;
  }
}

/// Best-effort bridge to the native payment-notification-detection feature
/// (Android only — see android/app/src/main/kotlin/.../paymentdetect/ and
/// MainActivity.kt's `payment_events` channel). Every method is safe to call
/// on any platform and never throws; failures are swallowed and return a
/// harmless default, matching `ShareReferrerReader`'s pattern in
/// lib/features/share/share_referrer_reader_io.dart.
abstract final class PaymentEventBridge {
  static const _channel = MethodChannel(
    'com.receiptdrop.receipt_drop/payment_events',
  );

  /// Master on/off for the whole feature (Profile → "Payment detection").
  /// Persisted natively so the listener honours it even when the Flutter
  /// engine isn't running. Defaults to true on the native side.
  static Future<bool> isPaymentDetectionEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'isPaymentDetectionEnabled',
      );
      return enabled ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> setPaymentDetectionEnabled(bool enabled) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setPaymentDetectionEnabled', enabled);
    } on Object {
      // Best-effort — the toggle state re-reads from native on next resume.
    }
  }

  static Future<bool> isNotificationAccessGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'isNotificationAccessGranted',
      );
      return granted ?? false;
    } on Object {
      return false;
    }
  }

  static Future<PaymentListenerStatus> notificationListenerStatus() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const PaymentListenerStatus.unavailable();
    }
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getNotificationListenerStatus',
      );
      if (raw == null) return const PaymentListenerStatus.unavailable();
      return PaymentListenerStatus.fromMap(raw);
    } on Object {
      return const PaymentListenerStatus.unavailable();
    }
  }

  static Future<void> openNotificationAccessSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
    } on Object {
      // Best-effort — nothing else to do if the settings screen can't open.
    }
  }

  static Future<void> openAutostartSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('openAutostartSettings');
    } on Object {
      // Best-effort — nothing else to do if the settings screen can't open.
    }
  }

  /// Whether the OS will let this app run while the device is dozing.
  ///
  /// Without the exemption, Doze holds notification-listener callbacks until
  /// the device next wakes: a payment made before an idle stretch is detected
  /// minutes to hours late, or seemingly "only when you open the app" (which
  /// is itself just what wakes the process). This is the difference between
  /// the feature working and appearing to fire at random.
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final ignored = await _channel.invokeMethod<bool>(
        'isBatteryOptimizationIgnored',
      );
      return ignored ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } on Object {
      // Best-effort — the state re-reads from native on next resume.
    }
  }

  static Future<bool> isOverlayPermissionGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final granted = await _channel.invokeMethod<bool>(
        'isOverlayPermissionGranted',
      );
      return granted ?? false;
    } on Object {
      return false;
    }
  }

  static Future<void> openOverlayPermissionSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('openOverlayPermissionSettings');
    } on Object {
      // Best-effort — nothing else to do if the settings screen can't open.
    }
  }

  static Future<List<QueuedPaymentEvent>> drainPaymentEvents() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'drainPaymentEvents',
      );
      if (raw == null) return const [];
      return [
        for (final item in raw)
          QueuedPaymentEvent.fromMap(item! as Map<Object?, Object?>),
      ];
    } on Object {
      return const [];
    }
  }

  static Future<void> acknowledgePaymentEvents(List<String> ids) async {
    if (ids.isEmpty) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('acknowledgePaymentEvents', ids);
    } on Object {
      // Best-effort — an un-acked id is simply drained (and re-ingested,
      // idempotently by fingerprint dedup on the native side) next launch.
    }
  }
}
