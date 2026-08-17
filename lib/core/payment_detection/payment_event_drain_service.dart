import 'package:flutter/foundation.dart';

import '../../data/repositories/ingest_receipt_request.dart';
import '../bootstrap/app_services.dart';
import 'payment_event_bridge.dart';

/// Drains payment events that were captured natively (Google Wallet
/// notification detected, category picked on the floating overlay) while
/// the Flutter engine wasn't running, and saves each as a real transaction
/// through the normal repository — this is the only place a notification-
/// derived event ever calls into `ingestReceipt`; the native side never
/// touches Drift/Supabase itself. Call once on app startup.
abstract final class PaymentEventDrainService {
  static Future<void> drainAndIngest() async {
    try {
      final events = await PaymentEventBridge.drainPaymentEvents();
      if (events.isEmpty) return;

      final ackIds = <String>[];
      for (final event in events) {
        try {
          await AppServices.transactions.ingestReceipt(
            IngestReceiptRequest(
              amountMyr: event.amountMyr,
              needsAmount: false,
              merchantRaw: event.merchantRaw,
              categoryGuess: event.category,
              categoryUser: event.category,
              notes: 'Auto-detected from ${event.sourcePackage}',
            ),
          );
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
    }
  }
}
