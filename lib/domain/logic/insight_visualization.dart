/// Chart types the backend's Visualization Story Agent may emit. Kept in
/// sync with `services/ocr-api/ocr_api/insights/visualization_agent.py`'s
/// `_VIZ_RULES` and the `curate-insights` Edge Function's closed vocabulary.
/// `location_heatmap` is an allowed wire value but no rule emits it today,
/// so it has no widget yet — treated the same as an unknown type below.
enum InsightVisualKind { lineTrend, beforeAfterBar, habitTimeline, forecastProjection }

/// Dispatches a raw visualization map (or null) to the chart kind that
/// should render it. Never throws — malformed/unsupported input yields null,
/// which callers render as nothing (never a placeholder/fabricated chart).
InsightVisualKind? insightVisualKind(Map<String, dynamic>? visualization) {
  switch (visualization?['type']) {
    case 'line_trend':
      return InsightVisualKind.lineTrend;
    case 'before_after_bar':
      return InsightVisualKind.beforeAfterBar;
    case 'habit_timeline':
      return InsightVisualKind.habitTimeline;
    case 'forecast_projection':
      return InsightVisualKind.forecastProjection;
    default:
      return null;
  }
}
