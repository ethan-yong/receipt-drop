import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/models/insight_candidate.dart';
import '../local/app_database.dart';

/// Reads/writes the local spending-insights mirror and syncs dismissals up.
class InsightsRepository {
  InsightsRepository(this._db);

  final AppDatabase _db;

  Stream<List<CuratedInsight>> watchActive() {
    return (_db.select(_db.localSpendingInsights)
          ..where((t) => t.dismissed.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.rank),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch()
        .map((rows) => rows.map(_mapRow).toList());
  }

  Future<List<CuratedInsight>> getActive() async {
    final rows = await (_db.select(_db.localSpendingInsights)
          ..where((t) => t.dismissed.equals(false))
          ..orderBy([
            (t) => OrderingTerm.asc(t.rank),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
    return rows.map(_mapRow).toList();
  }

  /// Per fact_key dismissal counts for curator personalization.
  Future<Map<String, int>> dismissCountsByFactKey() async {
    final rows = await (_db.select(_db.localSpendingInsights)
          ..where((t) => t.dismissed.equals(true)))
        .get();
    final counts = <String, int>{};
    for (final r in rows) {
      counts[r.factKey] = (counts[r.factKey] ?? 0) + 1;
    }
    return counts;
  }

  /// User feedback payload for the curator Edge Function.
  Future<Map<String, dynamic>> curatorFeedbackPayload() async {
    final dismissed = await dismissedFactKeys();
    final counts = await dismissCountsByFactKey();
    return {
      'dismissed_fact_keys': dismissed.toList(),
      'dismiss_counts': counts,
    };
  }

  Future<Set<String>> dismissedFactKeys() async {
    final rows = await (_db.select(_db.localSpendingInsights)
          ..where((t) => t.dismissed.equals(true)))
        .get();
    return {for (final r in rows) r.factKey};
  }

  /// Fact keys shown in the most recent generation cycle (non-dismissed).
  Future<Set<String>> recentActiveFactKeys() async {
    final rows = await (_db.select(_db.localSpendingInsights)
          ..where((t) => t.dismissed.equals(false)))
        .get();
    return {for (final r in rows) r.factKey};
  }

  Future<void> upsertCurated(List<CuratedInsight> insights, String userId) async {
    if (insights.isEmpty) return;
    await _db.batch((batch) {
      for (final insight in insights) {
        batch.insert(
          _db.localSpendingInsights,
          LocalSpendingInsightsCompanion.insert(
            id: insight.id,
            userId: userId,
            insightType: insight.type,
            factKey: insight.factKey,
            body: insight.body,
            rank: Value(insight.rank),
            dismissed: const Value(false),
            visualizationJson: Value(
              insight.visualization == null
                  ? null
                  : jsonEncode(insight.visualization),
            ),
            createdAt: Value(insight.createdAt),
            syncStatus: const Value('synced'),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Optimistic dismiss — UI removes immediately; sync-up is fire-and-forget.
  Future<void> dismissLocally(String id) async {
    await (_db.update(_db.localSpendingInsights)
          ..where((t) => t.id.equals(id)))
        .write(
      LocalSpendingInsightsCompanion(
        dismissed: const Value(true),
        dismissedAt: Value(DateTime.now()),
        syncStatus: const Value('pending'),
      ),
    );
  }

  Future<List<LocalSpendingInsight>> pendingDismissals() async {
    return (_db.select(_db.localSpendingInsights)
          ..where(
            (t) =>
                t.dismissed.equals(true) & t.syncStatus.equals('pending'),
          ))
        .get();
  }

  Future<void> markDismissSynced(String id) async {
    await (_db.update(_db.localSpendingInsights)
          ..where((t) => t.id.equals(id)))
        .write(
      const LocalSpendingInsightsCompanion(syncStatus: Value('synced')),
    );
  }

  CuratedInsight _mapRow(LocalSpendingInsight row) {
    return CuratedInsight(
      id: row.id,
      type: row.insightType,
      factKey: row.factKey,
      body: row.body,
      rank: row.rank,
      createdAt: row.createdAt,
      dismissed: row.dismissed,
      visualization: row.visualizationJson == null
          ? null
          : Map<String, dynamic>.from(
              jsonDecode(row.visualizationJson!) as Map,
            ),
    );
  }
}

/// Pure helper: parse curator Edge Function response into curated insights.
List<CuratedInsight> parseCuratorResponse(Object? data) {
  if (data is! Map) return const [];
  final raw = data['insights'];
  if (raw is! List) return const [];
  return [
    for (final item in raw) CuratedInsight.tryFromJson(item),
  ].whereType<CuratedInsight>().toList();
}
