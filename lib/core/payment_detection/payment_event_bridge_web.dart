/// Web/no-op counterpart to `payment_event_bridge_io.dart`. Payment
/// notification detection is Android-only, so every method here is a no-op.
class QueuedPaymentEvent {
  const QueuedPaymentEvent({
    required this.id,
    required this.merchantRaw,
    required this.amountMyr,
    required this.category,
    required this.sourcePackage,
    required this.occurredAt,
    required this.fingerprint,
  });

  final String id;
  final String merchantRaw;
  final double amountMyr;
  final String category;
  final String sourcePackage;
  final DateTime occurredAt;
  final String fingerprint;
}

abstract final class PaymentEventBridge {
  static Future<bool> isNotificationAccessGranted() async => false;

  static Future<void> openNotificationAccessSettings() async {}

  static Future<bool> isOverlayPermissionGranted() async => false;

  static Future<void> openOverlayPermissionSettings() async {}

  static Future<List<QueuedPaymentEvent>> drainPaymentEvents() async =>
      const [];

  static Future<void> acknowledgePaymentEvents(List<String> ids) async {}
}
