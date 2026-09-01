import 'package:flutter/foundation.dart';

import '../../data/repositories/ingest_receipt_request.dart';
import '../bootstrap/app_services.dart';
import 'payment_event_bridge.dart';

/// Drains payment events captured natively (payment notification detected,
/// category picked on the floating overlay) and saves each as a real
/// transaction through the normal repository — this is the only place a
/// notification-derived event ever calls into `ingestReceipt`; the native
/// side never touches Drift/Supabase itself.
///
/// Must be called both at startup *and* on every resume. The notification
/// listener keeps the app's process alive indefinitely, so a startup-only
/// drain can go days without running: the user picks a category, the event is
/// queued natively, and it stays queued because the Flutter engine is never
/// recreated. See [PaymentEventDrainListener].
abstract final class PaymentEventDrainService {
  /// Guards against two drains overlapping (startup racing the first resume),
  /// which would ingest the same event twice — the native queue is only
  /// cleared by the ack that follows a successful save.
  static bool _draining = false;

  static Future<void> drainAndIngest() async {
    if (_draining) return;
    _draining = true;
    try {
      final events = await PaymentEventBridge.drainPaymentEvents();
      if (events.isEmpty) return;

      final ackIds = <String>[];
      for (final event in events) {
        try {
          await AppServices.transactions.ingestReceipt(requestFor(event));
          ackIds.add(event.id);
        } on Object catch (e) {
          debugPrint(
            'PaymentEventDrainService: failed to ingest ${event.id}: $e',
          );
          // Left un-acked — retried on the next drain.
        }
      }

      if (ackIds.isNotEmpty) {
        await PaymentEventBridge.acknowledgePaymentEvents(ackIds);
      }
    } on Object catch (e) {
      debugPrint('PaymentEventDrainService.drainAndIngest: $e');
    } finally {
      _draining = false;
    }
  }

  @visibleForTesting
  static IngestReceiptRequest requestFor(QueuedPaymentEvent event) {
    // An event with no category is one the overlay never got to ask about
    // (the OS delivered the notification too late to interrupt over). Saving
    // it under a guess as though it were confirmed would quietly put wrong
    // data in the user's history, so it goes to the review queue instead —
    // surfaced by home_screen.dart's needs-review banner.
    final category = event.category ?? event.suggestedCategory ?? 'Others';
    return IngestReceiptRequest(
      amountMyr: event.amountMyr,
      needsAmount: false,
      merchantRaw: event.merchantRaw,
      categoryGuess: category,
      categoryUser: event.needsReview ? null : category,
      needsReview: event.needsReview,
      // The queue is durable across process death, so this can be well in the
      // past by the time it drains.
      occurredAt: event.occurredAt,
      notes: 'Auto-detected from ${event.sourcePackage}',
    );
  }
}
