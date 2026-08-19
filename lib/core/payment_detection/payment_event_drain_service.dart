import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/ingest_receipt_request.dart';
import '../bootstrap/app_services.dart';
import '../config/env.dart';
import 'payment_event_bridge.dart';

/// Drains payment events that were captured natively (payment notification
/// detected, category picked on the floating overlay) while the Flutter
/// engine wasn't running, and saves each as a real transaction through the
/// normal repository — this is the only place a notification-derived event
/// ever calls into `ingestReceipt`; the native side never touches Drift/
/// Supabase itself.
///
/// Call on cold start, on app resume, and after auth session restore — the
/// overlay can fire while the process is still alive in the background, so
/// startup-only draining leaves picked categories stranded in the native
/// queue until the user force-stops the app.
abstract final class PaymentEventDrainService {
  static bool _draining = false;

  static Future<void> drainAndIngest() async {
    if (_draining) return;
    _draining = true;
    try {
      final events = await PaymentEventBridge.drainPaymentEvents();
      if (events.isEmpty) return;

      final userId = _resolveUserId();
      if (userId == null) {
        debugPrint(
          'PaymentEventDrainService: session not ready, '
          '${events.length} queued event(s) left for retry',
        );
        return;
      }

      final ackIds = <String>[];
      for (final event in events) {
        try {
          await AppServices.transactions.ingestReceipt(
            IngestReceiptRequest(
              userId: userId,
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
    } finally {
      _draining = false;
    }
  }

  static String? _resolveUserId() {
    if (Env.hasSupabaseConfig) {
      final authId = Supabase.instance.client.auth.currentUser?.id;
      if (authId != null) return authId;
    }
    if (Env.skipAuth) return 'demo-user';
    return null;
  }
}
