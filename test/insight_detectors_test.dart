import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/insight_detectors.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';
import 'package:receipt_drop/data/repositories/insights_repository.dart';
import 'package:receipt_drop/data/repositories/insights_worker.dart';

TransactionView _tx({
  required String id,
  required DateTime occurredAt,
  double amount = 10,
  String category = 'Food & Drink',
  String? categoryUser,
  double? categoryConfidence,
  String? placeName,
  double? placeLat,
  double? placeLng,
  String pipelineStatus = 'enriched',
}) {
  return TransactionView(
    id: id,
    occurredAt: occurredAt,
    amountMyr: amount,
    needsAmount: false,
    merchantRaw: placeName ?? 'Merchant',
    categoryGuess: category,
    categoryUser: categoryUser,
    placeName: placeName,
    placeGooglePlaceId: placeLat != null ? 'place-$id' : null,
    placeLat: placeLat,
    placeLng: placeLng,
    syncStatus: 'synced',
    pipelineStatus: pipelineStatus,
    localThumbnailPath: null,
    categoryConfidence: categoryConfidence,
  );
}

void main() {
  group('detectSpendingSpikes', () {
    test('emits nothing without a weekday baseline', () {
      final now = DateTime(2026, 7, 28); // Tuesday
      final rows = [
        _tx(id: '1', occurredAt: now, amount: 100),
      ];
      expect(detectSpendingSpikes(rows, now: now), isEmpty);
    });

    test('emits when today is at least 2x weekday baseline', () {
      final now = DateTime(2026, 7, 28, 18); // Tuesday
      final rows = <TransactionView>[
        // Prior Tuesdays — enough for baseline (~20 avg)
        for (var w = 1; w <= 4; w++)
          _tx(
            id: 'prev-$w',
            occurredAt: now.subtract(Duration(days: 7 * w)),
            amount: 20,
          ),
        _tx(id: 'today', occurredAt: now, amount: 50), // 2.5x
      ];
      final hits = detectSpendingSpikes(rows, now: now);
      expect(hits, hasLength(1));
      expect(hits.single.type, 'spending_spike');
      expect(hits.single.facts['multiplier'], greaterThanOrEqualTo(2.0));
    });

    test('does not emit exactly below threshold', () {
      final now = DateTime(2026, 7, 28, 18);
      final rows = <TransactionView>[
        for (var w = 1; w <= 4; w++)
          _tx(
            id: 'prev-$w',
            occurredAt: now.subtract(Duration(days: 7 * w)),
            amount: 20,
          ),
        _tx(id: 'today', occurredAt: now, amount: 30), // 1.5x < 2.0
      ];
      expect(detectSpendingSpikes(rows, now: now), isEmpty);
    });
  });

  group('detectCategoryShifts', () {
    test('emits nothing with zero prior-week data', () {
      final now = DateTime(2026, 7, 28);
      final rows = [
        _tx(id: '1', occurredAt: now, amount: 50, category: 'Groceries'),
      ];
      expect(detectCategoryShifts(rows, now: now), isEmpty);
    });

    test('emits when week-over-week category delta clears thresholds', () {
      final now = DateTime(2026, 7, 28); // Tue
      final thisWeek = DateTime(2026, 7, 27); // Mon of this week
      final lastWeek = DateTime(2026, 7, 20); // Mon of last week
      final rows = [
        _tx(
          id: 'prev',
          occurredAt: lastWeek,
          amount: 50,
          category: 'Food & Drink',
        ),
        _tx(
          id: 'cur',
          occurredAt: thisWeek,
          amount: 100,
          category: 'Food & Drink',
        ),
      ];
      final hits = detectCategoryShifts(rows, now: now);
      expect(hits, isNotEmpty);
      expect(hits.first.type, 'category_shift');
      expect(hits.first.facts['direction'], 'up');
    });
  });

  group('detectHabits', () {
    test('emits nothing below minimum visit count', () {
      final now = DateTime(2026, 7, 28);
      final rows = [
        for (var i = 0; i < kHabitMinVisits - 1; i++)
          TransactionView(
            id: 'v-$i',
            occurredAt: now.subtract(Duration(days: i)),
            amountMyr: 10,
            needsAmount: false,
            merchantRaw: 'Tealive',
            categoryGuess: 'Food & Drink',
            categoryUser: null,
            placeName: 'Tealive',
            placeGooglePlaceId: 'same-place-id',
            placeLat: 3.1,
            placeLng: 101.6,
            syncStatus: 'synced',
            pipelineStatus: 'enriched',
            localThumbnailPath: null,
          ),
      ];
      expect(detectHabits(rows, now: now), isEmpty);
    });

    test('emits at exactly the minimum visit count', () {
      final now = DateTime(2026, 7, 28);
      final rows = [
        for (var i = 0; i < kHabitMinVisits; i++)
          TransactionView(
            id: 'v-$i',
            occurredAt: now.subtract(Duration(days: i)),
            amountMyr: 10,
            needsAmount: false,
            merchantRaw: 'Tealive SS2',
            categoryGuess: 'Food & Drink',
            categoryUser: null,
            placeName: 'Tealive SS2',
            placeGooglePlaceId: 'same-place-id',
            placeLat: 3.1,
            placeLng: 101.6,
            syncStatus: 'synced',
            pipelineStatus: 'enriched',
            localThumbnailPath: null,
          ),
      ];
      final hits = detectHabits(rows, now: now);
      expect(hits, hasLength(1));
      expect(hits.single.type, 'habit');
      expect(hits.single.facts['visits'], kHabitMinVisits);
    });
  });

  group('detectStreakMotivation', () {
    test('does not fire on day 1', () {
      final now = DateTime(2026, 7, 28);
      final rows = [_tx(id: '1', occurredAt: now)];
      expect(detectStreakMotivation(rows, now: now), isEmpty);
    });

    test('fires at the minimum streak threshold', () {
      final now = DateTime(2026, 7, 28, 12);
      final rows = [
        for (var i = 0; i < kMinStreakDays; i++)
          _tx(id: 'd-$i', occurredAt: now.subtract(Duration(days: i))),
      ];
      final hits = detectStreakMotivation(rows, now: now);
      expect(hits, hasLength(1));
      expect(hits.single.facts['streak_days'], kMinStreakDays);
    });
  });

  group('detectForecast', () {
    test('emits nothing without a prior month', () {
      final now = DateTime(2026, 7, 15);
      final rows = [
        _tx(id: '1', occurredAt: DateTime(2026, 7, 1), amount: 100),
        _tx(id: '2', occurredAt: DateTime(2026, 7, 10), amount: 100),
      ];
      expect(detectForecast(rows, now: now), isEmpty);
    });

    test('emits when projected pace clearly exceeds prior month', () {
      final now = DateTime(2026, 7, 10);
      final rows = <TransactionView>[
        // June total 100
        _tx(id: 'jun1', occurredAt: DateTime(2026, 6, 5), amount: 50),
        _tx(id: 'jun2', occurredAt: DateTime(2026, 6, 20), amount: 50),
        // July so far: 80 in 10 days → projected ~248
        _tx(id: 'jul1', occurredAt: DateTime(2026, 7, 2), amount: 40),
        _tx(id: 'jul2', occurredAt: DateTime(2026, 7, 8), amount: 40),
      ];
      final hits = detectForecast(rows, now: now);
      expect(hits, hasLength(1));
      expect(hits.single.type, 'forecast');
    });
  });

  group('detectInsightCandidates', () {
    test('suppresses fact keys in the dismissed set', () {
      final now = DateTime(2026, 7, 28, 12);
      final rows = [
        for (var i = 0; i < kMinStreakDays; i++)
          _tx(id: 'd-$i', occurredAt: now.subtract(Duration(days: i))),
      ];
      final all = detectInsightCandidates(rows, now: now);
      expect(all, isNotEmpty);
      final key = all.first.factKey;
      final filtered = detectInsightCandidates(
        rows,
        now: now,
        suppressedFactKeys: {key},
      );
      expect(filtered.any((c) => c.factKey == key), isFalse);
    });

    test('excludes needs_review rows', () {
      final now = DateTime(2026, 7, 28, 12);
      final rows = [
        for (var i = 0; i < kMinStreakDays; i++)
          _tx(
            id: 'd-$i',
            occurredAt: now.subtract(Duration(days: i)),
            pipelineStatus: 'needs_review',
            amount: 10,
          ),
      ];
      // needs_review with amount still has includeInCharts true, but
      // insightEligibleRows explicitly excludes needs_review.
      expect(insightEligibleRows(rows), isEmpty);
    });
  });

  group('parseCuratorResponse', () {
    test('accepts a valid curated payload', () {
      final parsed = parseCuratorResponse({
        'insights': [
          {
            'id': 'abc',
            'type': 'streak',
            'fact_key': 'streak:3:2026-07-28',
            'body': 'You logged receipts 3 days in a row',
            'rank': 0,
            'created_at': '2026-07-28T00:00:00Z',
          },
        ],
      });
      expect(parsed, hasLength(1));
      expect(parsed.single.type, 'streak');
    });

    test('rejects unknown type tags', () {
      final parsed = parseCuratorResponse({
        'insights': [
          {
            'id': 'abc',
            'type': 'budget_warning',
            'fact_key': 'x',
            'body': 'Stop spending',
            'rank': 0,
            'created_at': '2026-07-28T00:00:00Z',
          },
        ],
      });
      expect(parsed, isEmpty);
    });

    test('rejects malformed JSON shapes', () {
      expect(parseCuratorResponse(null), isEmpty);
      expect(parseCuratorResponse('nope'), isEmpty);
      expect(parseCuratorResponse({'insights': 'x'}), isEmpty);
    });
  });

  group('InsightsWorker.guardPassesForTest', () {
    test('does not double-fire within the window', () {
      final last = DateTime(2026, 7, 28, 10);
      final now = last.add(const Duration(hours: 2));
      expect(
        InsightsWorker.guardPassesForTest(
          lastGeneratedAt: last,
          syncedTxSinceLastCycle: 1,
          now: now,
        ),
        isFalse,
      );
    });

    test('fires once the time threshold is met', () {
      final last = DateTime(2026, 7, 28, 10);
      final now = last.add(Duration(hours: kInsightsMinHoursBetweenCycles));
      expect(
        InsightsWorker.guardPassesForTest(
          lastGeneratedAt: last,
          syncedTxSinceLastCycle: 0,
          now: now,
        ),
        isTrue,
      );
    });

    test('fires on volume threshold after at least one hour', () {
      final last = DateTime(2026, 7, 28, 10);
      final now = last.add(const Duration(hours: 2));
      expect(
        InsightsWorker.guardPassesForTest(
          lastGeneratedAt: last,
          syncedTxSinceLastCycle: kInsightsMinNewSyncedTx,
          now: now,
        ),
        isTrue,
      );
    });
  });

  group('templateCurate', () {
    test('caps at 3 insights', () {
      final candidates = [
        for (var i = 0; i < 5; i++)
          detectStreakMotivation(
            [
              for (var d = 0; d < kMinStreakDays + i; d++)
                _tx(
                  id: '$i-$d',
                  occurredAt: DateTime(2026, 7, 28).subtract(Duration(days: d)),
                ),
            ],
            now: DateTime(2026, 7, 28),
          ),
      ].expand((e) => e).toList();
      // Build synthetic pool instead if streak keys collide.
      final pool = detectInsightCandidates([
        for (var d = 0; d < 10; d++)
          _tx(
            id: 's-$d',
            occurredAt: DateTime(2026, 7, 28).subtract(Duration(days: d)),
          ),
        for (var w = 1; w <= 4; w++)
          _tx(
            id: 'base-$w',
            occurredAt: DateTime(2026, 7, 28).subtract(Duration(days: 7 * w)),
            amount: 20,
          ),
        _tx(id: 'spike', occurredAt: DateTime(2026, 7, 28, 18), amount: 80),
      ], now: DateTime(2026, 7, 28, 18));
      final curated = templateCurate(pool, maxInsights: 3);
      expect(curated.length, lessThanOrEqualTo(3));
      expect(candidates, isNotEmpty); // silence unused warning if pool empty
    });
  });
}
