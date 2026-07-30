import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/insight_visualization.dart';

/// Renders the one small visual a curated insight's backend visualization
/// spec calls for — never a dashboard, never more than one chart. Renders
/// nothing for a null/unsupported/malformed spec rather than a placeholder.
class InsightVisualization extends StatelessWidget {
  const InsightVisualization({super.key, required this.visualization});

  final Map<String, dynamic>? visualization;

  @override
  Widget build(BuildContext context) {
    final kind = insightVisualKind(visualization);
    if (kind == null) return const SizedBox.shrink();

    final parametersRaw = visualization!['parameters'];
    final params = parametersRaw is Map
        ? Map<String, dynamic>.from(parametersRaw)
        : const <String, dynamic>{};
    final animationRaw = visualization!['animation'];
    final durationMs =
        animationRaw is Map && animationRaw['duration_ms'] is num
            ? (animationRaw['duration_ms'] as num).round().clamp(200, 2000)
            : 800;

    switch (kind) {
      case InsightVisualKind.lineTrend:
        return _LineTrendVisual.fromParameters(params, durationMs: durationMs);
      case InsightVisualKind.beforeAfterBar:
        return _BeforeAfterBarVisual.fromParameters(
          params,
          durationMs: durationMs,
        );
      case InsightVisualKind.habitTimeline:
        return _HabitTimelineVisual.fromParameters(
          params,
          durationMs: durationMs,
        );
      case InsightVisualKind.forecastProjection:
        return _ForecastProjectionVisual.fromParameters(
          params,
          durationMs: durationMs,
        );
    }
  }
}

AxisTitles get _hiddenAxis =>
    const AxisTitles(sideTitles: SideTitles(showTitles: false));

// ---------------------------------------------------------------------------
// spending_spike -> line_trend (animation: line_draw)
// ---------------------------------------------------------------------------

class _LineTrendVisual extends StatelessWidget {
  const _LineTrendVisual({
    required this.weekday,
    required this.baseline,
    required this.todayTotal,
    required this.durationMs,
  });

  static Widget fromParameters(
    Map<String, dynamic> params, {
    required int durationMs,
  }) {
    final weekday = params['weekday'];
    final baseline = params['baseline'];
    final todayTotal = params['today_total'];
    if (weekday is! String || baseline is! num || todayTotal is! num) {
      return const SizedBox.shrink();
    }
    return _LineTrendVisual(
      weekday: weekday,
      baseline: baseline.toDouble(),
      todayTotal: todayTotal.toDouble(),
      durationMs: durationMs,
    );
  }

  final String weekday;
  final double baseline;
  final double todayTotal;
  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(baseline, todayTotal) * 1.3 + 1;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 110,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: durationMs),
        curve: Curves.easeOutBack,
        builder: (context, t, _) {
          final revealedToday = baseline + (todayTotal - baseline) * t;
          return LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: _hiddenAxis,
                rightTitles: _hiddenAxis,
                leftTitles: _hiddenAxis,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt() == 0 ? 'Usual $weekday' : 'Today',
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [FlSpot(0, baseline), FlSpot(1, revealedToday)],
                  color: AppColors.accentOrange,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppColors.accentOrange.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// category_shift -> before_after_bar (animation: bars_grow)
// ---------------------------------------------------------------------------

class _BeforeAfterBarVisual extends StatefulWidget {
  const _BeforeAfterBarVisual({
    required this.category,
    required this.previous,
    required this.current,
    required this.durationMs,
  });

  static Widget fromParameters(
    Map<String, dynamic> params, {
    required int durationMs,
  }) {
    final category = params['category'];
    final previous = params['previous'];
    final current = params['current'];
    if (category is! String || previous is! num || current is! num) {
      return const SizedBox.shrink();
    }
    return _BeforeAfterBarVisual(
      category: category,
      previous: previous.toDouble(),
      current: current.toDouble(),
      durationMs: durationMs,
    );
  }

  final String category;
  final double previous;
  final double current;
  final int durationMs;

  @override
  State<_BeforeAfterBarVisual> createState() => _BeforeAfterBarVisualState();
}

class _BeforeAfterBarVisualState extends State<_BeforeAfterBarVisual> {
  bool _previousShown = false;
  bool _currentShown = false;

  @override
  void initState() {
    super.initState();
    final step = Duration(milliseconds: (widget.durationMs / 2).round());
    // Previous bar first, current bar grows in shortly after — per bars_grow.
    Future.delayed(Duration.zero, () {
      if (mounted) setState(() => _previousShown = true);
    });
    Future.delayed(step, () {
      if (mounted) setState(() => _currentShown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(widget.previous, widget.current) * 1.3 + 1;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.category, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 110,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: _hiddenAxis,
                rightTitles: _hiddenAxis,
                leftTitles: _hiddenAxis,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt() == 0 ? 'Before' : 'Now',
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: _previousShown ? widget.previous : 0,
                      color: AppColors.textMuted,
                      width: 28,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: _currentShown ? widget.current : 0,
                      color: AppColors.accentOrange,
                      width: 28,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ],
            ),
            duration: Duration(milliseconds: (widget.durationMs / 2).round()),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// habit -> habit_timeline (animation: icons_pop)
// ---------------------------------------------------------------------------

class _HabitTimelineVisual extends StatefulWidget {
  const _HabitTimelineVisual({
    required this.placeName,
    required this.visits,
    required this.windowDays,
    required this.durationMs,
  });

  static Widget fromParameters(
    Map<String, dynamic> params, {
    required int durationMs,
  }) {
    final placeName = params['place_name'];
    final visits = params['visits'];
    final windowDays = params['window_days'];
    if (placeName is! String || visits is! num || windowDays is! num) {
      return const SizedBox.shrink();
    }
    return _HabitTimelineVisual(
      placeName: placeName,
      // Cap the icon row — this is an illustrative timeline, not a ledger.
      visits: visits.round().clamp(1, 14),
      windowDays: windowDays.round(),
      durationMs: durationMs,
    );
  }

  final String placeName;
  final int visits;
  final int windowDays;
  final int durationMs;

  @override
  State<_HabitTimelineVisual> createState() => _HabitTimelineVisualState();
}

class _HabitTimelineVisualState extends State<_HabitTimelineVisual> {
  late final List<bool> _visible = List.filled(widget.visits, false);

  @override
  void initState() {
    super.initState();
    final stagger = Duration(
      milliseconds: (widget.durationMs / widget.visits).round(),
    );
    for (var i = 0; i < widget.visits; i++) {
      Future.delayed(stagger * i, () {
        if (mounted) setState(() => _visible[i] = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: List.generate(widget.visits, (i) {
            final visible = _visible[i];
            return AnimatedScale(
              scale: visible ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: const CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.creamDark,
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 16,
                    color: AppColors.primaryGreenDark,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${widget.placeName} · last ${widget.windowDays} days',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// forecast -> forecast_projection (animation: forecast_reveal)
// ---------------------------------------------------------------------------

class _ForecastProjectionVisual extends StatefulWidget {
  const _ForecastProjectionVisual({
    required this.currentSoFar,
    required this.projected,
    required this.durationMs,
  });

  static Widget fromParameters(
    Map<String, dynamic> params, {
    required int durationMs,
  }) {
    final currentSoFar = params['current_so_far'];
    final projected = params['projected'];
    if (currentSoFar is! num || projected is! num) {
      return const SizedBox.shrink();
    }
    return _ForecastProjectionVisual(
      currentSoFar: currentSoFar.toDouble(),
      projected: projected.toDouble(),
      durationMs: durationMs,
    );
  }

  final double currentSoFar;
  final double projected;
  final int durationMs;

  @override
  State<_ForecastProjectionVisual> createState() =>
      _ForecastProjectionVisualState();
}

class _ForecastProjectionVisualState extends State<_ForecastProjectionVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _actualReveal;
  late final Animation<double> _forecastFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.durationMs),
    )..forward();
    // Actual line draws first, forecast fades in afterward — forecast_reveal.
    _actualReveal = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
    );
    _forecastFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.55, 1.0, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(widget.projected, widget.currentSoFar) * 1.2 + 1;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 110,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final actualY = widget.currentSoFar * _actualReveal.value;
          return LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: _hiddenAxis,
                rightTitles: _hiddenAxis,
                leftTitles: _hiddenAxis,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i == 0) return Text('So far', style: labelStyle);
                      if (i == 2) return Text('Projected', style: labelStyle);
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [const FlSpot(0, 0), FlSpot(1, actualY)],
                  color: AppColors.primaryGreenDark,
                  barWidth: 3,
                  dotData: const FlDotData(show: true),
                ),
                LineChartBarData(
                  spots: [
                    FlSpot(1, widget.currentSoFar),
                    FlSpot(2, widget.projected),
                  ],
                  color: AppColors.accentOrange.withValues(
                    alpha: _forecastFade.value,
                  ),
                  barWidth: 3,
                  dashArray: const [6, 4],
                  dotData: const FlDotData(show: true),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
