import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/dashboard_aggregates.dart';

class CategoryDonutChart extends StatelessWidget {
  const CategoryDonutChart({
    super.key,
    required this.slices,
    this.animate = true,
  });

  final List<CategorySlice> slices;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('No spend this month')),
      );
    }

    final colors = slices
        .map((s) => AppColors.categoryColor(s.category))
        .toList();

    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: List.generate(slices.length, (i) {
                  final total =
                      slices.fold<double>(0, (a, s) => a + s.amount);
                  final pct = total > 0 ? (slices[i].amount / total) * 100 : 0;
                  return PieChartSectionData(
                    value: slices[i].amount,
                    color: colors[i],
                    radius: 52,
                    title: pct > 8 ? '${pct.toStringAsFixed(0)}%' : '',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  );
                }),
              ),
              duration: animate
                  ? const Duration(milliseconds: 800)
                  : Duration.zero,
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: slices.take(5).map((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.categoryColor(s.category),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.category,
                          style: Theme.of(context).textTheme.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class WeeklyLineChart extends StatelessWidget {
  const WeeklyLineChart({super.key, required this.points});

  final List<WeekPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(height: 120);
    }

    final maxY = points.fold<double>(
      0,
      (m, p) => p.amount > m ? p.amount : m,
    );

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.2 + 1,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    points[i].label,
                    style: Theme.of(context).textTheme.labelSmall,
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                points.length,
                (i) => FlSpot(i.toDouble(), points[i].amount),
              ),
              isCurved: true,
              color: AppColors.primaryGreen,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.primaryGreen.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 600),
      ),
    );
  }
}

class TopPlacesList extends StatelessWidget {
  const TopPlacesList({super.key, required this.places});

  final List<TopPlaceRow> places;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return Text(
        'No places with location yet',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final fmt = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);

    return Column(
      children: places.map((p) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${p.visitCount} visits',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                fmt.format(p.totalSpend),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
