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
  });
}
