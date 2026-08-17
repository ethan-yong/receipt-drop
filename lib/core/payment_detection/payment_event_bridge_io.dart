import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A payment event captured natively (Google Wallet notification detected,
/// user picked a category from the floating overlay) and durably queued on
/// the Android side, waiting for Flutter to save it as a real transaction.
/// See android/app/src/main/kotlin/.../paymentdetect/PaymentEventQueueStore.kt.
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

  factory QueuedPaymentEvent.fromMap(Map<Object?, Object?> map) {
    return QueuedPaymentEvent(
      id: map['id'] as String,
      merchantRaw: map['merchantRaw'] as String,
      amountMyr: (map['amountMyr'] as num).toDouble(),
      category: map['category'] as String,
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
  final String category;
  final String sourcePackage;
  final DateTime occurredAt;
  final String fingerprint;
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

  static Future<void> openNotificationAccessSettings() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
    } on Object {
      // Best-effort — nothing else to do if the settings screen can't open.
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
