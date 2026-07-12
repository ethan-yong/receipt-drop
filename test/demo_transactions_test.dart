import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/repositories/demo_transactions.dart';

void main() {
  group('receiptShowcaseTransactions', () {
    test('seeded times are never ahead of the wall clock', () {
      final rows = receiptShowcaseTransactions();
      final now = DateTime.now();

      for (final row in rows) {
        expect(
          row.occurredAt.isAfter(now),
          isFalse,
          reason:
              '${row.id} was seeded in the future (${row.occurredAt}); '
              'a receipt captured right after seeding would sort behind it',
        );
      }
    });

    test('seeded times all fall on today', () {
      final rows = receiptShowcaseTransactions();
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);

      expect(rows, hasLength(kReceiptShowcaseCategories.length));
      for (final row in rows) {
        expect(
          row.occurredAt.isBefore(startOfToday),
          isFalse,
          reason: '${row.id} fell out of the todaysTransactions window',
        );
      }
    });
  });
}
