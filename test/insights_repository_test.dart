import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/local/app_database.dart';
import 'package:receipt_drop/data/repositories/insights_repository.dart';
import 'package:receipt_drop/domain/models/insight_candidate.dart';

void main() {
  group('InsightsRepository curator feedback', () {
    late AppDatabase db;
    late InsightsRepository repo;

    setUp(() {
      db = AppDatabase.memory();
      repo = InsightsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertInsight({
      required String id,
      required String factKey,
      required bool dismissed,
    }) async {
      await db.into(db.localSpendingInsights).insert(
            LocalSpendingInsightsCompanion.insert(
              id: id,
              userId: 'user-1',
              insightType: 'streak',
              factKey: factKey,
              body: 'Test body',
              dismissed: Value(dismissed),
            ),
          );
    }

    test('curatorFeedbackPayload aggregates dismissed keys and counts', () async {
      await insertInsight(
        id: 'a',
        factKey: 'streak:3:2026-07-28',
        dismissed: true,
      );
      await insertInsight(
        id: 'b',
        factKey: 'streak:3:2026-07-28',
        dismissed: true,
      );
      await insertInsight(
        id: 'c',
        factKey: 'habit:tealive:2026-07-28',
        dismissed: true,
      );
      await insertInsight(
        id: 'd',
        factKey: 'forecast:2026-07',
        dismissed: false,
      );

      final payload = await repo.curatorFeedbackPayload();

      expect(
        payload['dismissed_fact_keys'],
        containsAll([
          'streak:3:2026-07-28',
          'habit:tealive:2026-07-28',
        ]),
      );
      expect(payload['dismiss_counts'], {
        'streak:3:2026-07-28': 2,
        'habit:tealive:2026-07-28': 1,
      });
    });
  });

  group('CuratedInsight.tryFromJson', () {
    test('maps title and description to body', () {
      final insight = CuratedInsight.tryFromJson({
        'id': '1',
        'type': 'streak',
        'fact_key': 'streak:3',
        'title': 'Nice streak',
        'description': 'You logged 3 days in a row.',
        'rank': 0,
        'created_at': '2026-07-28T10:00:00Z',
      });
      expect(insight, isA<CuratedInsight>());
      expect(
        insight!.body,
        'Nice streak. You logged 3 days in a row.',
      );
    });

    test('parses a visualization object when present', () {
      final insight = CuratedInsight.tryFromJson({
        'id': '1',
        'type': 'category_shift',
        'fact_key': 'shift:Food:2026-07-28',
        'body': 'Food spend is up this week.',
        'rank': 0,
        'created_at': '2026-07-28T10:00:00Z',
        'visualization': {
          'type': 'before_after_bar',
          'data_source': 'weekly_category_totals',
          'parameters': {'category': 'Food', 'previous': 110.0, 'current': 150.0},
          'highlight': {'metric': 'percent_change', 'focus': 'current'},
          'animation': {'type': 'bars_grow', 'duration_ms': 700},
        },
      });
      expect(insight!.visualization, isNotNull);
      expect(insight.visualization!['type'], 'before_after_bar');
    });

    test('leaves visualization null when absent or malformed', () {
      final missing = CuratedInsight.tryFromJson({
        'id': '1',
        'type': 'streak',
        'fact_key': 'streak:3',
        'body': 'You logged 3 days in a row.',
        'rank': 0,
        'created_at': '2026-07-28T10:00:00Z',
      });
      expect(missing!.visualization, isNull);

      final malformed = CuratedInsight.tryFromJson({
        'id': '1',
        'type': 'streak',
        'fact_key': 'streak:3',
        'body': 'You logged 3 days in a row.',
        'rank': 0,
        'created_at': '2026-07-28T10:00:00Z',
        'visualization': 'not a map',
      });
      expect(malformed!.visualization, isNull);
    });
  });

  group('InsightsRepository visualization round-trip', () {
    late AppDatabase db;
    late InsightsRepository repo;

    setUp(() {
      db = AppDatabase.memory();
      repo = InsightsRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertCurated persists visualization and getActive decodes it',
        () async {
      final withViz = CuratedInsight(
        id: 'i1',
        type: 'habit',
        factKey: 'habit:tealive:2026-07-28',
        body: 'You visit Tealive often.',
        rank: 0,
        createdAt: DateTime(2026, 7, 28),
        visualization: const {
          'type': 'habit_timeline',
          'data_source': 'place_visit_frequency',
          'parameters': {
            'place_name': 'Tealive',
            'visits': 4,
            'window_days': 7,
          },
          'highlight': {'metric': 'visits', 'focus': 'latest'},
          'animation': {'type': 'icons_pop', 'duration_ms': 600},
        },
      );
      final withoutViz = CuratedInsight(
        id: 'i2',
        type: 'streak',
        factKey: 'streak:3:2026-07-28',
        body: '3-day streak!',
        rank: 1,
        createdAt: DateTime(2026, 7, 28),
      );

      await repo.upsertCurated([withViz, withoutViz], 'user-1');
      final active = await repo.getActive();
      final byId = {for (final i in active) i.id: i};

      expect(byId['i1']!.visualization, isNotNull);
      expect(byId['i1']!.visualization!['type'], 'habit_timeline');
      expect(
        byId['i1']!.visualization!['parameters'],
        {'place_name': 'Tealive', 'visits': 4, 'window_days': 7},
      );
      expect(byId['i2']!.visualization, isNull);
    });
  });
}
