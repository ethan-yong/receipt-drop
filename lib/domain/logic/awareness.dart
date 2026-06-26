import '../models/transaction_view.dart';
import 'impact_level.dart';

/// Port of Impact Drops' `awareness.ts`, re-keyed to operate over real
/// `TransactionView` rows for "today" instead of the mock's in-session
/// `Drop[]` (matching the windowing already used for avatar mood).
class AwarenessSummary {
  const AwarenessSummary({required this.headline, required this.sub});

  final String headline;
  final String sub;
}

const _lines = [
  'Compared to last week at this time, your activity feels calmer.',
  "Your most impactful drop today was less intense than your weekend average.",
  'You had fewer high-impact moments than last Tuesday.',
  "Today's rhythm is steadier than your usual mid-week pattern.",
  'Your activity clustered around fewer categories than yesterday.',
  'A quieter day than most — closer to your calm baseline.',
  'More spread out than last week — a balanced kind of day.',
  'Your impact peaks today were softer than the past few days.',
];

AwarenessSummary awarenessSummary(List<TransactionView> todaysRows) {
  final high = todaysRows
      .where((t) => t.effectiveImpactLevel == ImpactLevel.high)
      .length;
  final total = todaysRows.length;

  final String headline;
  if (total == 0) {
    headline = 'A quiet day. Nothing dropped yet.';
  } else if (high >= 2) {
    headline = 'Today had more intensity than usual.';
  } else if (total >= 4) {
    headline = 'A busy rhythm — many small moments.';
  } else {
    headline = 'A steady, balanced day.';
  }

  final idx = (total * 3 + high * 7) % _lines.length;
  return AwarenessSummary(headline: headline, sub: _lines[idx]);
}

/// "Vs. last week" classification shown alongside the headline.
String awarenessIntensity(List<TransactionView> todaysRows) {
  final high = todaysRows
      .where((t) => t.effectiveImpactLevel == ImpactLevel.high)
      .length;
  final total = todaysRows.length;

  if (high >= 2) return 'More intense';
  if (total >= 4) return 'Busier';
  if (total <= 2) return 'Calmer';
  return 'Balanced';
}
