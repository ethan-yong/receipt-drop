import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/logic/dashboard_aggregates.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/category_donut_chart.dart';
import '../../widgets/friends_teaser_card.dart';
import '../../widgets/month_picker_header.dart';
import '../../widgets/platform_refresh_scroll_view.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shiftMonth(int delta) {
    PlatformFeedback.selectionTap();
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
  }

  Future<void> _refresh() async {
    await AppServices.transactions.retryStuckSync();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: const Text('Dashboard')),
      body: StreamBuilder<List<TransactionView>>(
        stream: AppServices.transactions.watchAll(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          final summary = monthSummary(rows, _month);
          final categories = categoryBreakdown(rows, _month);
          final weeks = weeklyTrend(rows, _month);
          final places = topPlaces(rows, _month);
          final fmt = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);

          return PlatformRefreshScrollView(
            onRefresh: _refresh,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  100,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    MonthPickerHeader(
                      month: _month,
                      onPrevious: () => _shiftMonth(-1),
                      onNext: () => _shiftMonth(1),
                    ),
                    Text(
                      'This Month',
                      style: Theme.of(context).textTheme.labelMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      fmt.format(summary.total),
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: AppColors.primaryGreen,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    if (summary.deltaPercent != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${summary.deltaPercent! >= 0 ? '+' : ''}${summary.deltaPercent!.toStringAsFixed(0)}% vs last month',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: summary.deltaPercent! >= 0
                                  ? AppColors.destructive
                                  : AppColors.primaryGreen,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    _sectionTitle(context, 'By Category'),
                    Card(
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: CategoryDonutChart(slices: categories),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _sectionTitle(context, 'By Week'),
                    Card(
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: WeeklyLineChart(points: weeks),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _sectionTitle(context, 'Top Places'),
                    Card(
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: TopPlacesList(places: places),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const FriendsTeaserCard(),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
