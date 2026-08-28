/// Web/no-op counterpart to `payment_event_bridge_io.dart`. Payment
/// notification detection is Android-only, so every method here is a no-op.
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

  final String id;
  final String merchantRaw;
  final double amountMyr;
  final String? category;
  final String? suggestedCategory;
  final String sourcePackage;
  final DateTime occurredAt;
  final String fingerprint;

  bool get needsReview => category == null;
}

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

  final bool granted;
  final bool active;
  final bool neverConnected;
  final DateTime? lastNotificationAt;

  PaymentListenerState get state => PaymentListenerState.notGranted;
}

abstract final class PaymentEventBridge {
  static Future<bool> isPaymentDetectionEnabled() async => false;

  static Future<void> setPaymentDetectionEnabled(bool enabled) async {}

  static Future<bool> isNotificationAccessGranted() async => false;

  static Future<PaymentListenerStatus> notificationListenerStatus() async =>
      const PaymentListenerStatus.unavailable();

  static Future<void> openNotificationAccessSettings() async {}

  static Future<void> openAutostartSettings() async {}

  static Future<bool> isBatteryOptimizationIgnored() async => false;

  static Future<void> requestIgnoreBatteryOptimizations() async {}

  static Future<bool> isOverlayPermissionGranted() async => false;

  static Future<void> openOverlayPermissionSettings() async {}

  static Future<List<QueuedPaymentEvent>> drainPaymentEvents() async =>
      const [];

  static Future<void> acknowledgePaymentEvents(List<String> ids) async {}
}
