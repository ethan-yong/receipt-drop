/// At-a-glance headline metric shown in an insight card's header, derived
/// only from values already present in the insight's own visualization
/// parameters — never fabricated beyond what the backend attached.
enum InsightBadgeDirection { up, down, neutral }

class InsightBadge {
  const InsightBadge({required this.label, required this.direction});

  final String label;
  final InsightBadgeDirection direction;
}

/// Returns the small metric badge for [type]'s card header, or null when the
/// visualization is missing/malformed. Mirrors `insightVisualKind`'s
/// never-fabricate contract: insufficient data means no badge, not a guess.
InsightBadge? insightBadgeFor(
  String type,
  Map<String, dynamic>? visualization,
) {
  if (visualization == null) return null;
  final parametersRaw = visualization['parameters'];
  if (parametersRaw is! Map) return null;
  final p = parametersRaw;

  switch (type) {
    case 'spending_spike':
      final baseline = p['baseline'];
      final todayTotal = p['today_total'];
      if (baseline is! num || todayTotal is! num || baseline <= 0) {
        return null;
      }
      final pct = ((todayTotal / baseline - 1) * 100).round();
      if (pct <= 0) return null;
      return InsightBadge(label: '$pct%', direction: InsightBadgeDirection.up);

    case 'category_shift':
      final previous = p['previous'];
      final current = p['current'];
      if (previous is! num || current is! num || previous <= 0) return null;
      final pct = (((current - previous).abs() / previous) * 100).round();
      return InsightBadge(
        label: '$pct%',
        direction: current >= previous
            ? InsightBadgeDirection.up
            : InsightBadgeDirection.down,
      );

    case 'habit':
      final visits = p['visits'];
      if (visits is! num) return null;
      return InsightBadge(
        label: '${visits.round()}×',
        direction: InsightBadgeDirection.neutral,
      );

    case 'forecast':
      final projected = p['projected'];
      if (projected is! num) return null;
      return InsightBadge(
        label: 'RM${projected.round()}',
        direction: InsightBadgeDirection.neutral,
      );

    default:
      return null;
  }
}
