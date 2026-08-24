import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/bill_split_reminder_message.dart';

void main() {
  group('buildWhatsAppReminderMessage', () {
    test('equal-split mode (no assigned items) states the flat share', () {
      final message = buildWhatsAppReminderMessage(
        recipientName: 'Sarah',
        merchantOrPlace: 'KFC',
        receiptDate: DateTime(2026, 8, 24),
        assignedItems: const [],
        totalOwedMyr: 30.00,
      );
      expect(message, '''
Hi Sarah!
Just a reminder for your share from KFC on 24 Aug.

Your share: RM 30.00

Sent via Receipt Drop'''
          .trim());
    });

    test('by-item mode lists each assigned item then the total', () {
      final message = buildWhatsAppReminderMessage(
        recipientName: 'Sarah',
        merchantOrPlace: 'KFC',
        receiptDate: DateTime(2026, 8, 24),
        assignedItems: const [
          (label: 'Chicken Burger', priceMyr: 18.00),
          (label: 'Fries', priceMyr: 7.00),
          (label: 'Drink', priceMyr: 5.00),
        ],
        totalOwedMyr: 30.00,
      );
      expect(message, '''
Hi Sarah!
Just a reminder for your share from KFC on 24 Aug.

Chicken Burger — RM 18.00
Fries — RM 7.00
Drink — RM 5.00

Total: RM 30.00

Sent via Receipt Drop'''
          .trim());
    });

    test('is deterministic — identical inputs always produce an identical string', () {
      ({String label, double priceMyr}) item = (label: 'Nasi Lemak', priceMyr: 8.50);
      String build() => buildWhatsAppReminderMessage(
            recipientName: 'John',
            merchantOrPlace: 'Warung Pak Ali',
            receiptDate: DateTime(2026, 1, 2),
            assignedItems: [item],
            totalOwedMyr: 8.50,
          );
      expect(build(), build());
    });

    test('never includes another recipient\'s items or amount', () {
      final message = buildWhatsAppReminderMessage(
        recipientName: 'John',
        merchantOrPlace: 'KFC',
        receiptDate: DateTime(2026, 8, 24),
        assignedItems: const [(label: 'Fries', priceMyr: 3.50)],
        totalOwedMyr: 3.50,
      );
      expect(message.contains('Chicken Burger'), false);
      expect(message.contains('30.00'), false);
    });
  });
}
