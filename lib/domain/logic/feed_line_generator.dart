import 'dart:math';

import '../models/transaction_view.dart';
import 'impact_level.dart';

const _highLines = [
  'dropped a luxury-level impact today',
  'logged a high-impact moment',
  'had a big one today',
];

const _medLines = [
  'logged a steady, balanced afternoon',
  'kept a mid-impact pace today',
  'dropped a fair-sized one',
];

const _lowLines = [
  'had a low activity day — calm energy',
  'kept it quiet — observer mode',
  'dropped a gentle one today',
];

const _categoryFlavor = {
  'Food & Drink': 'over food',
  'Groceries': 'on a grocery run',
  'Transport': 'on the road',
};

final _random = Random();

/// Generates the only text ever shown about a friend's drop in the feed —
/// deliberately derived from impact tier + category alone, never the raw
/// amount or merchant name (see migration 20260626000002_social.sql, which
/// only lets `feed_posts.line` cross the RLS boundary between users).
/// Called once at save time, so a fresh random pick (rather than a
/// deterministic formula) is fine — the result is persisted, not recomputed.
String generateFeedLine(TransactionView transaction) {
  final lines = switch (transaction.effectiveImpactLevel) {
    ImpactLevel.high => _highLines,
    ImpactLevel.med => _medLines,
    ImpactLevel.low => _lowLines,
  };
  final line = lines[_random.nextInt(lines.length)];
  final flavor = _categoryFlavor[transaction.effectiveCategory];
  return flavor == null ? line : '$line $flavor';
}
