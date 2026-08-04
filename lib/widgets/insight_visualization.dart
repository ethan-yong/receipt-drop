import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

const _insightTooltipBg = AppColors.textPrimary;
const _insightTooltipTextStyle = TextStyle(
  color: AppColors.scaffold,
  fontWeight: FontWeight.w600,
  fontSize: 12,
);
const _holdToViewDelay = Duration(milliseconds: 120);

String _formatInsightValue(double value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}

bool _insightHoldActive(FlTouchEvent event) =>
    event is FlLongPressStart || event is FlLongPressMoveUpdate;

bool _insightHoldReleased(FlTouchEvent event) =>
    event is FlLongPressEnd ||
    event is FlTapUpEvent ||
    event is FlTapCancelEvent ||
    event is FlPointerExitEvent ||
    event is FlPanEndEvent ||
    event is FlPanCancelEvent;

LineTouchData _insightLineTouchData(
  void Function(FlTouchEvent, LineTouchResponse?) onTouch,
) =>
    LineTouchData(
      enabled: true,
      handleBuiltInTouches: false,
      longPressDuration: _holdToViewDelay,
      touchCallback: onTouch,
      touchTooltipData: LineTouchTooltipData(
        tooltipRoundedRadius: 8,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipMargin: 6,
        getTooltipColor: (_) => _insightTooltipBg,
        getTooltipItems: (spots) => spots
            .map(
              (spot) => LineTooltipItem(
                _formatInsightValue(spot.y),
                _insightTooltipTextStyle,
              ),
            )
            .toList(),
      ),
    );

String _formatInsightRm(double value) {
  final rounded = value.round();
  if ((value - rounded).abs() < 0.01) {
    return 'RM$rounded';
  }
  return 'RM${value.toStringAsFixed(0)}';
}

/// Horizontal inset so endpoint dots and edge labels aren't clipped.
const _forecastChartHorizontalPad = 0.2;

FlDotData _forecastDot(Color color) => FlDotData(
      show: true,
      getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
        radius: 4,
        color: color,
        strokeWidth: 2,
        strokeColor: AppColors.textPrimary,
      ),
    );

String _forecastMonthDate(DateTime date) => DateFormat('d MMM').format(date);

Widget _forecastBottomLabel({
  required String caption,
  required String date,
  required TitleMeta meta,
  required TextStyle captionStyle,
  required TextStyle dateStyle,
  required CrossAxisAlignment align,
}) {
  return SideTitleWidget(
    axisSide: meta.axisSide,
    space: 2,
    fitInside: SideTitleFitInsideData.disable(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        Text(
          caption,
          style: captionStyle,
          maxLines: 1,
          softWrap: false,
        ),
        Text(
          date,
          style: dateStyle,
          maxLines: 1,
          softWrap: false,
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// spending_spike -> line_trend (animation: line_draw)
// ---------------------------------------------------------------------------

class _LineTrendVisual extends StatefulWidget {
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
  State<_LineTrendVisual> createState() => _LineTrendVisualState();
}

class _LineTrendVisualState extends State<_LineTrendVisual> {
  List<ShowingTooltipIndicators> _heldTooltips = const [];

  void _onTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (_insightHoldReleased(event)) {
      setState(() => _heldTooltips = const []);
      return;
    }
    final spots = response?.lineBarSpots;
    if (_insightHoldActive(event) && spots != null && spots.isNotEmpty) {
      setState(() => _heldTooltips = [ShowingTooltipIndicators(spots)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(widget.baseline, widget.todayTotal) * 1.3 + 1;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      height: 110,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: widget.durationMs),
        curve: Curves.easeOutBack,
        builder: (context, t, _) {
          final revealedToday =
              widget.baseline + (widget.todayTotal - widget.baseline) * t;
          return LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY,
              showingTooltipIndicators: _heldTooltips,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: _insightLineTouchData(_onTouch),
              titlesData: FlTitlesData(
                topTitles: _hiddenAxis,
                rightTitles: _hiddenAxis,
                leftTitles: _hiddenAxis,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) => Text(
                      v.round() == 0 ? 'Usual ${widget.weekday}' : 'Today',
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [
                    FlSpot(0, widget.baseline),
                    FlSpot(1, revealedToday),
                  ],
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

const _comparisonBarPrevious = Color(0xFFF2E7D5);
const _comparisonBarCurrent = Color(0xFF8BA9A3);
const _comparisonBarAspectRatio = 1.35;
const _comparisonBarWidthFactor = 0.5;

class _BeforeAfterBarVisual extends StatefulWidget {
  const _BeforeAfterBarVisual({
    required this.previous,
    required this.current,
    required this.previousLabel,
    required this.currentLabel,
    required this.durationMs,
  });

  static Widget fromParameters(
    Map<String, dynamic> params, {
    required int durationMs,
  }) {
    final previous = params['previous'];
    final current = params['current'];
    if (previous is! num || current is! num) {
      return const SizedBox.shrink();
    }
    final previousLabel = params['previous_label'];
    final currentLabel = params['current_label'];
    return _BeforeAfterBarVisual(
      previous: previous.toDouble(),
      current: current.toDouble(),
      previousLabel: previousLabel is String ? previousLabel : 'Last month',
      currentLabel: currentLabel is String ? currentLabel : 'This month',
      durationMs: durationMs,
    );
  }

  final double previous;
  final double current;
  final String previousLabel;
  final String currentLabel;
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
    Future.delayed(Duration.zero, () {
      if (mounted) setState(() => _previousShown = true);
    });
    Future.delayed(step, () {
      if (mounted) setState(() => _currentShown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxValue = math.max(widget.previous, widget.current);
    final barDuration = Duration(milliseconds: (widget.durationMs / 2).round());

    return AspectRatio(
      aspectRatio: _comparisonBarAspectRatio,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _ComparisonBarColumn(
                value: widget.previous,
                maxValue: maxValue,
                label: widget.previousLabel,
                shown: _previousShown,
                barColor: _comparisonBarPrevious,
                animateDuration: barDuration,
                valueStyle: textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
                periodStyle: textTheme.labelSmall?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _ComparisonBarColumn(
                value: widget.current,
                maxValue: maxValue,
                label: widget.currentLabel,
                shown: _currentShown,
                barColor: _comparisonBarCurrent,
                animateDuration: barDuration,
                valueStyle: textTheme.labelMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
                periodStyle: textTheme.labelSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonBarColumn extends StatelessWidget {
  const _ComparisonBarColumn({
    required this.value,
    required this.maxValue,
    required this.label,
    required this.shown,
    required this.barColor,
    required this.animateDuration,
    required this.valueStyle,
    required this.periodStyle,
  });

  final double value;
  final double maxValue;
  final String label;
  final bool shown;
  final Color barColor;
  final Duration animateDuration;
  final TextStyle? valueStyle;
  final TextStyle? periodStyle;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue > 0 && shown ? value / maxValue : 0.0;

    return Column(
      children: [
        Text(
          _formatInsightRm(value),
          style: valueStyle,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barHeight = constraints.maxHeight * fraction.clamp(0.0, 1.0);
              return Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: animateDuration,
                  curve: Curves.easeOutCubic,
                  height: barHeight,
                  width: constraints.maxWidth * _comparisonBarWidthFactor,
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: periodStyle,
          textAlign: TextAlign.center,
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
  List<ShowingTooltipIndicators> _heldTooltips = const [];

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

  void _onTouch(FlTouchEvent event, LineTouchResponse? response) {
    if (_insightHoldReleased(event)) {
      setState(() => _heldTooltips = const []);
      return;
    }
    final spots = response?.lineBarSpots;
    if (_insightHoldActive(event) && spots != null && spots.isNotEmpty) {
      setState(() => _heldTooltips = [ShowingTooltipIndicators(spots)]);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(widget.projected, widget.currentSoFar) * 1.2 + 1;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.onDarkCardSecondary,
        );
    final dateStyle = labelStyle?.copyWith(
      color: AppColors.onDarkCardSecondary.withValues(alpha: 0.75),
      fontSize: (labelStyle.fontSize ?? 11) - 1,
    );
    return SizedBox(
      height: 124,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final actualY = widget.currentSoFar * _actualReveal.value;
            final forecastColor = AppColors.accentOrange.withValues(
              alpha: _forecastFade.value,
            );
            return LineChart(
              LineChartData(
                minX: -_forecastChartHorizontalPad,
                maxX: 2 + _forecastChartHorizontalPad,
                minY: -maxY * 0.04,
                maxY: maxY,
                clipData: const FlClipData.none(),
                showingTooltipIndicators: _heldTooltips,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                lineTouchData: _insightLineTouchData(_onTouch),
                titlesData: FlTitlesData(
                  topTitles: _hiddenAxis,
                  rightTitles: _hiddenAxis,
                  leftTitles: _hiddenAxis,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 34,
                      getTitlesWidget: (v, meta) {
                        final i = v.round();
                        if (i == 0) {
                          return _forecastBottomLabel(
                            caption: 'So far',
                            date: _forecastMonthDate(monthStart),
                            meta: meta,
                            captionStyle: labelStyle ?? const TextStyle(),
                            dateStyle: dateStyle ?? const TextStyle(),
                            align: CrossAxisAlignment.start,
                          );
                        }
                        if (i == 2) {
                          return _forecastBottomLabel(
                            caption: 'Projected',
                            date: _forecastMonthDate(monthEnd),
                            meta: meta,
                            captionStyle: labelStyle ?? const TextStyle(),
                            dateStyle: dateStyle ?? const TextStyle(),
                            align: CrossAxisAlignment.end,
                          );
                        }
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
                    dotData: _forecastDot(AppColors.primaryGreenDark),
                  ),
                  LineChartBarData(
                    spots: [
                      FlSpot(1, widget.currentSoFar),
                      FlSpot(2, widget.projected),
                    ],
                    color: forecastColor,
                    barWidth: 3,
                    dashArray: const [6, 4],
                    dotData: _forecastDot(forecastColor),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
