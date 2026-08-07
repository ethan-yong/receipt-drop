import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/bill_split_math.dart';

void main() {
  group('splitCentsEvenly', () {
    test('divides evenly with no remainder', () {
      final shares = splitCentsEvenly(1000, ['a', 'b', 'c', 'd']);
      expect(shares, {'a': 250, 'b': 250, 'c': 250, 'd': 250});
    });

    test('distributes the remainder to the first N people in list order', () {
      final shares = splitCentsEvenly(1000, ['a', 'b', 'c']);
      expect(shares, {'a': 334, 'b': 333, 'c': 333});
      expect(shares.values.reduce((a, b) => a + b), 1000);
    });

    test('remainder distribution is order-sensitive', () {
      final shares = splitCentsEvenly(1000, ['c', 'a', 'b']);
      expect(shares, {'c': 334, 'a': 333, 'b': 333});
    });

    test('a single person gets the full amount', () {
      final shares = splitCentsEvenly(999, ['solo']);
      expect(shares, {'solo': 999});
    });

    test('throws on empty personIds', () {
      expect(() => splitCentsEvenly(1000, []), throwsArgumentError);
    });
  });

  group('splitEqual', () {
    test('rounds to cents and sums exactly to the total', () {
      final shares = splitEqual(totalMyr: 10.00, personIds: ['a', 'b', 'c']);
      expect(shares['a'], 3.34);
      expect(shares['b'], 3.33);
      expect(shares['c'], 3.33);
      final sum = shares.values.fold(0.0, (s, v) => s + v);
      expect(sum, closeTo(10.00, 0.001));
    });
  });

  group('splitByItems', () {
    test('a single item splits evenly among its assignees, summing to its price', () {
      final totals = splitByItems([
        const ItemAssignmentInput(
          lineItemId: 'i1',
          priceMyr: 10.00,
          assignedPersonIds: ['a', 'b'],
        ),
      ]);
      expect(totals, {'a': 5.00, 'b': 5.00});
    });

    test('multiple items are summed per person', () {
      final totals = splitByItems([
        const ItemAssignmentInput(
          lineItemId: 'i1',
          priceMyr: 10.00,
          assignedPersonIds: ['a', 'b'],
        ),
        const ItemAssignmentInput(
          lineItemId: 'i2',
          priceMyr: 6.00,
          assignedPersonIds: ['a'],
        ),
      ]);
      expect(totals['a'], 11.00);
      expect(totals['b'], 5.00);
    });

    test('a person on multiple items accumulates correctly across an odd split', () {
      final totals = splitByItems([
        const ItemAssignmentInput(
          lineItemId: 'i1',
          priceMyr: 10.00,
          assignedPersonIds: ['a', 'b', 'c'],
        ),
        const ItemAssignmentInput(
          lineItemId: 'i2',
          priceMyr: 10.00,
          assignedPersonIds: ['a', 'b', 'c'],
        ),
      ]);
      final sum = totals.values.fold(0.0, (s, v) => s + v);
      expect(sum, closeTo(20.00, 0.001));
    });

    test('throws on an item with empty assignedPersonIds', () {
      expect(
        () => splitByItems([
          const ItemAssignmentInput(
            lineItemId: 'i1',
            priceMyr: 10.00,
            assignedPersonIds: [],
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('whole-split invariant: sum of all people equals sum of all item prices', () {
      final items = [
        const ItemAssignmentInput(
          lineItemId: 'i1',
          priceMyr: 9.70,
          assignedPersonIds: ['a', 'b', 'c'],
        ),
        const ItemAssignmentInput(
          lineItemId: 'i2',
          priceMyr: 7.50,
          assignedPersonIds: ['b'],
        ),
        const ItemAssignmentInput(
          lineItemId: 'i3',
          priceMyr: 12.00,
          assignedPersonIds: ['a', 'c'],
        ),
      ];
      final totals = splitByItems(items);
      final expectedTotal = items.fold(0.0, (s, it) => s + it.priceMyr);
      final actualTotal = totals.values.fold(0.0, (s, v) => s + v);
      expect(actualTotal, closeTo(expectedTotal, 0.001));
    });
  });
}
