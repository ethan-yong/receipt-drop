import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/config/env.dart';
import '../../domain/logic/insight_detectors.dart';
import '../../domain/models/insight_candidate.dart';
import '../../domain/models/transaction_view.dart';
import '../local/app_database.dart';
import 'insights_repository.dart';

/// Minimum hours between curator LLM cycles.
const kInsightsMinHoursBetweenCycles = 6;

/// Minimum newly-synced transactions since the last cycle to re-trigger.
const kInsightsMinNewSyncedTx = 2;

/// Soft-launch: skip the LLM curator and use template strings instead.
/// Flip to false once the Edge Function + ocr-api `/curate-insights` is live.
const kInsightsUseTemplateFallback = false;

/// Background worker: after a successful sync, maybe generate spending insights.
///
/// Structurally parallel to [SyncWorker] — fire-`unawaited`, re-entrancy guarded,
/// never throws into the caller, never blocks receipt sync.
class InsightsWorker {
  InsightsWorker._();

  static bool _running = false;

  /// Called from [SyncWorker.run]'s success path. Loads transactions via
  /// [loadTransactions], runs detectors, and optionally calls the curator.
  static Future<void> run(
    AppDatabase db, {
    required Future<List<TransactionView>> Function() loadTransactions,
    InsightsRepository? insightsRepo,
  }) async {
    if (!Env.hasSupabaseConfig && !kInsightsUseTemplateFallback) return;
    if (_running) return;
    _running = true;

    try {
      final userId = _resolveUserId();
      if (userId == null) return;

      final repo = insightsRepo ?? InsightsRepository(db);

      await _syncPendingDismissals(repo);

      if (!_guardPasses()) return;

      final rows = await loadTransactions();
      final suppressed = <String>{
        ...await repo.dismissedFactKeys(),
        ...await repo.recentActiveFactKeys(),
      };

      final candidates = detectInsightCandidates(
        rows,
        suppressedFactKeys: suppressed,
      );
      if (candidates.isEmpty) {
        await AppPrefs.setInsightsLastGeneratedAt(DateTime.now());
        return;
      }

      final List<CuratedInsight> curated;
      if (kInsightsUseTemplateFallback) {
        curated = templateCurate(candidates);
      } else {
        final feedback = await repo.curatorFeedbackPayload();
        curated = await _callCurator(
          candidates,
          dismissedFactKeys: (feedback['dismissed_fact_keys'] as List)
              .cast<String>(),
          dismissCounts:
              Map<String, int>.from(feedback['dismiss_counts'] as Map),
        ) ??
            const [];
      }

      if (curated.isEmpty) return;

      final previous = await repo.getActive();
      for (final old in previous) {
        if (curated.any((c) => c.factKey == old.factKey)) continue;
        await repo.dismissLocally(old.id);
        await repo.markDismissSynced(old.id);
      }

      await repo.upsertCurated(curated, userId);
      await AppPrefs.setInsightsLastGeneratedAt(DateTime.now());
      await AppPrefs.setInsightsSyncedTxSinceLastCycle(0);
    } catch (_) {
      // Silent degrade — never surface to the user or fail the sync path.
    } finally {
      _running = false;
    }
  }

  /// Call after each successful transaction sync so the volume guard can fire.
  static Future<void> noteSyncedTransaction() async {
    final n = AppPrefs.insightsSyncedTxSinceLastCycle + 1;
    await AppPrefs.setInsightsSyncedTxSinceLastCycle(n);
  }

  static bool _guardPasses() {
    final last = AppPrefs.insightsLastGeneratedAt;
    final newTx = AppPrefs.insightsSyncedTxSinceLastCycle;
    if (last == null) {
      return newTx >= 1;
    }
    final hours = DateTime.now().difference(last).inHours;
    if (hours >= kInsightsMinHoursBetweenCycles) return true;
    if (newTx >= kInsightsMinNewSyncedTx && hours >= 1) return true;
    return false;
  }

  /// Exposed for unit tests of the time/volume gate.
  static bool guardPassesForTest({
    DateTime? lastGeneratedAt,
    int syncedTxSinceLastCycle = 0,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    if (lastGeneratedAt == null) {
      return syncedTxSinceLastCycle >= 1;
    }
    final hours = clock.difference(lastGeneratedAt).inHours;
    if (hours >= kInsightsMinHoursBetweenCycles) return true;
    if (syncedTxSinceLastCycle >= kInsightsMinNewSyncedTx && hours >= 1) {
      return true;
    }
    return false;
  }

  static Future<List<CuratedInsight>?> _callCurator(
    List<InsightCandidate> candidates, {
    required List<String> dismissedFactKeys,
    required Map<String, int> dismissCounts,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'curate-insights',
        body: {
          'candidates': [for (final c in candidates) c.toJson()],
          'dismissed_fact_keys': dismissedFactKeys,
          'dismiss_counts': dismissCounts,
        },
      );
      if (response.status != 200) return null;
      return parseCuratorResponse(response.data);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _syncPendingDismissals(InsightsRepository repo) async {
    if (!Env.hasSupabaseConfig) return;
    final pending = await repo.pendingDismissals();
    for (final row in pending) {
      try {
        await Supabase.instance.client.from('spending_insights').update({
          'dismissed': true,
          'dismissed_at':
              (row.dismissedAt ?? DateTime.now()).toUtc().toIso8601String(),
        }).eq('id', row.id);
        await repo.markDismissSynced(row.id);
      } catch (_) {
        // Retry next cycle.
      }
    }
  }

  static String? _resolveUserId() {
    if (!Env.hasSupabaseConfig) {
      if (Env.skipAuth) return 'demo-user';
      return null;
    }
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null) return authId;
    if (Env.skipAuth) return 'demo-user';
    return null;
  }

  /// Test helper: clear the re-entrancy flag.
  static void resetForTest() {
    _running = false;
  }
}
