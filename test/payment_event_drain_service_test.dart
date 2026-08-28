import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/payment_detection/payment_event_bridge.dart';
import 'package:receipt_drop/core/payment_detection/payment_event_drain_service.dart';

/// Covers how a natively-captured payment becomes a transaction.
///
/// The queue is durable across process death, so an event can reach here long
/// after the payment — and it may never have been categorized at all, when the
/// OS delivered the notification too late for the overlay to ask.
void main() {
  QueuedPaymentEvent event({
    String? category = 'Food & Drink',
    String? suggestedCategory,
    DateTime? occurredAt,
  }) {
    return QueuedPaymentEvent(
      id: 'id-1',
      merchantRaw: 'KOPITIAM SS15',
      amountMyr: 12.30,
      category: category,
      suggestedCategory: suggestedCategory,
      sourcePackage: 'com.maybank2u.life',
      occurredAt: occurredAt ?? DateTime(2026, 8, 29, 13, 45),
      fingerprint: 'fp-1',
    );
  }

  group('PaymentEventDrainService.requestFor', () {
    test('saves a user-categorized event as a settled transaction', () {
      final request = PaymentEventDrainService.requestFor(event());

      expect(request.categoryUser, 'Food & Drink');
      expect(request.categoryGuess, 'Food & Drink');
      expect(request.needsReview, isFalse);
      expect(request.amountMyr, 12.30);
      expect(request.merchantRaw, 'KOPITIAM SS15');
      expect(request.needsAmount, isFalse);
    });

    test('files the transaction under the payment time, not the drain time', () {
      final paidAt = DateTime(2026, 8, 28, 9, 15);

      final request = PaymentEventDrainService.requestFor(
        event(occurredAt: paidAt),
      );

      expect(request.occurredAt, paidAt);
    });

    test('routes an uncategorized event to the review queue', () {
      // Nobody confirmed a category, so saving it as settled would quietly
      // put a guess into the user's spending history.
      final request = PaymentEventDrainService.requestFor(
        event(category: null, suggestedCategory: 'Transport'),
      );

      expect(request.needsReview, isTrue);
      expect(request.categoryUser, isNull);
      expect(request.categoryGuess, 'Transport');
    });

    test('falls back to Others when there is no category or suggestion', () {
      final request = PaymentEventDrainService.requestFor(
        event(category: null, suggestedCategory: null),
      );

      expect(request.needsReview, isTrue);
      expect(request.categoryGuess, 'Others');
      expect(request.categoryUser, isNull);
    });

    test('records where the payment came from', () {
      final request = PaymentEventDrainService.requestFor(event());

      expect(request.notes, contains('com.maybank2u.life'));
    });
  });
}
