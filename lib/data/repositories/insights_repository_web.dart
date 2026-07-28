import 'dart:async';

import '../../domain/models/insight_candidate.dart';

/// Web stub — no Drift mirror; insights are empty until a future web path.
class InsightsRepository {
  Stream<List<CuratedInsight>> watchActive() => Stream.value(const []);

  Future<List<CuratedInsight>> getActive() async => const [];

  Future<Set<String>> dismissedFactKeys() async => {};

  Future<Set<String>> recentActiveFactKeys() async => {};

  Future<void> upsertCurated(List<CuratedInsight> insights, String userId) async {}

  Future<void> dismissLocally(String id) async {}

  Future<void> markDismissSynced(String id) async {}
}
