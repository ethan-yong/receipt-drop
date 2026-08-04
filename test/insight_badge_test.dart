import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/insight_badge.dart';

void main() {
  test('spending_spike badge computes percent-up from visualization params', () {
    final badge = insightBadgeFor('spending_spike', {
      'type': 'line_trend',
      'parameters': {'weekday': 'Tuesday', 'baseline': 91.0, 'today_total': 148.0},
    });
    expect(badge, isNotNull);
    expect(badge!.label, '63%');
    expect(badge.direction, InsightBadgeDirection.up);
  });

  test('category_shift badge direction flips on decrease', () {
    final up = insightBadgeFor('category_shift', {
      'parameters': {'category': 'Groceries', 'previous': 306.0, 'current': 410.0},
    });
    expect(up!.direction, InsightBadgeDirection.up);

    final down = insightBadgeFor('category_shift', {
      'parameters': {'category': 'Groceries', 'previous': 410.0, 'current': 306.0},
    });
    expect(down!.direction, InsightBadgeDirection.down);
  });

  test('habit badge is a neutral visit count', () {
    final badge = insightBadgeFor('habit', {
      'parameters': {'place_name': 'Starbucks', 'visits': 5, 'window_days': 7},
    });
    expect(badge!.label, '5×');
    expect(badge.direction, InsightBadgeDirection.neutral);
  });

  test('forecast badge is a neutral projected amount', () {
    final badge = insightBadgeFor('forecast', {
      'parameters': {'prior_month': 1900.0, 'current_so_far': 1340.0, 'projected': 2180.0},
    });
    expect(badge!.label, 'RM2180');
    expect(badge.direction, InsightBadgeDirection.neutral);
  });

  test('spending_spike badge is null when spend is not actually above baseline', () {
    expect(
      insightBadgeFor('spending_spike', {
        'parameters': {'weekday': 'Tuesday', 'baseline': 100.0, 'today_total': 90.0},
      }),
      isNull,
    );
  });

  test('returns null on malformed/missing visualization', () {
    expect(insightBadgeFor('forecast', null), isNull);
    expect(insightBadgeFor('spending_spike', {'parameters': {}}), isNull);
    expect(insightBadgeFor('unknown_type', {'parameters': {'x': 1}}), isNull);
  });
}
