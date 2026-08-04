import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/receipt_history_theme.dart';
import '../../domain/logic/receipt_history_grouping.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_card.dart';

/// Standalone receipts-only history view (Today, always expanded, then
/// collapsible week → day sections) reached from Home's "VIEW HISTORY"
/// button. Distinct from `DashboardScreen`, which pairs the same receipt
/// list with month summary/category/trend charts.
///
/// Design: the `Receipt History.dc.html` handoff — see
/// `lib/core/theme/receipt_history_theme.dart` for its scoped palette.
class ReceiptHistoryScreen extends StatefulWidget {
  const ReceiptHistoryScreen({super.key});

  @override
  State<ReceiptHistoryScreen> createState() => _ReceiptHistoryScreenState();
}

class _ReceiptHistoryScreenState extends State<ReceiptHistoryScreen> {
  final _expandedWeeks = <DateTime>{};
  final _expandedDays = <DateTime>{};

  void _toggleWeek(HistoryWeek week) {
    setState(() {
      if (_expandedWeeks.remove(week.weekStart)) {
        for (final day in week.days) {
          _expandedDays.remove(day.date);
        }
      } else {
        _expandedWeeks.add(week.weekStart);
      }
    });
  }

  void _toggleDay(HistoryDay day) {
    setState(() {
      if (!_expandedDays.remove(day.date)) {
        _expandedDays.add(day.date);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReceiptHistoryColors.scaffold,
      body: SafeArea(
        child: StreamBuilder<List<TransactionView>>(
          stream: AppServices.transactions.watchAll(),
          builder: (context, snapshot) {
            final rows = snapshot.data ?? const [];
            final history = buildReceiptHistory(rows, DateTime.now());
            final maxWeekTotal = history.weeks.fold(
              0.0,
              (max, w) => w.total > max ? w.total : max,
            );

            return Column(
              children: [
                _Header(onBack: () => context.pop()),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ReceiptHistoryLayout.screenHPad,
                    10,
                    ReceiptHistoryLayout.screenHPad,
                    0,
                  ),
                  child: _WeekSummaryCard(
                    count: history.thisWeekCount,
                    total: history.thisWeekTotal,
                    onInsightsTap: () => context.pushNamed('insights'),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      ReceiptHistoryLayout.screenHPad,
                      24,
                      ReceiptHistoryLayout.screenHPad,
                      22,
                    ),
                    children: [
                      _TodaySection(items: history.today),
                      const SizedBox(height: 26),
                      for (final week in history.weeks) ...[
                        _WeekSection(
                          week: week,
                          expanded: _expandedWeeks.contains(week.weekStart),
                          maxWeekTotal: maxWeekTotal,
                          expandedDays: _expandedDays,
                          onToggle: () => _toggleWeek(week),
                          onToggleDay: _toggleDay,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, ReceiptHistoryLayout.screenHPad, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: ReceiptHistoryColors.ink),
            onPressed: onBack,
          ),
          const SizedBox(width: 2),
          Text(
            'Receipt History',
            style: receiptHistoryText(24, FontWeight.w800, letterSpacing: -0.4),
          ),
        ],
      ),
    );
  }
}

class _WeekSummaryCard extends StatelessWidget {
  const _WeekSummaryCard({
    required this.count,
    required this.total,
    required this.onInsightsTap,
  });

  final int count;
  final double total;
  final VoidCallback onInsightsTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: ReceiptHistoryLayout.summaryAspectRatio,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        decoration: BoxDecoration(
          color: ReceiptHistoryColors.ink,
          borderRadius: BorderRadius.circular(ReceiptHistoryLayout.summaryRadius),
          boxShadow: [
            BoxShadow(
              color: ReceiptHistoryColors.ink.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'THIS WEEK · $count RECEIPT${count == 1 ? '' : 'S'}',
              style: receiptHistoryText(
                11,
                FontWeight.w700,
                color: ReceiptHistoryColors.mutedLabel,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'RM${total.toStringAsFixed(2)}',
              style: receiptHistoryText(
                34,
                FontWeight.w800,
                color: ReceiptHistoryColors.gold,
                letterSpacing: -0.6,
                height: 1.05,
              ),
            ),
            const Spacer(),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onInsightsTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.trending_up,
                        size: 15,
                        color: ReceiptHistoryColors.gold,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Insights',
                        style: receiptHistoryText(
                          12,
                          FontWeight.w800,
                          color: ReceiptHistoryColors.gold,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TodaySection extends StatelessWidget {
  const _TodaySection({required this.items});

  final List<TransactionView> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'TODAY',
            style: receiptHistoryText(
              11,
              FontWeight.w800,
              color: ReceiptHistoryColors.mutedLabel,
              letterSpacing: 1.6,
            ),
          ),
        ),
        if (items.isEmpty)
          Text(
            'No receipts yet today',
            style: receiptHistoryText(
              13,
              FontWeight.w600,
              color: ReceiptHistoryColors.mutedText,
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.only(left: 18),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: ReceiptHistoryColors.timelineLine, width: 2),
              ),
            ),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _HistoryItemRow(tx: items[i], isLast: i == items.length - 1),
              ],
            ),
          ),
      ],
    );
  }
}

class _WeekSection extends StatelessWidget {
  const _WeekSection({
    required this.week,
    required this.expanded,
    required this.maxWeekTotal,
    required this.expandedDays,
    required this.onToggle,
    required this.onToggleDay,
  });

  final HistoryWeek week;
  final bool expanded;
  final double maxWeekTotal;
  final Set<DateTime> expandedDays;
  final VoidCallback onToggle;
  final ValueChanged<HistoryDay> onToggleDay;

  @override
  Widget build(BuildContext context) {
    final zero = week.total == 0;
    final pct = maxWeekTotal > 0 ? week.total / maxWeekTotal : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: const Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: ReceiptHistoryColors.mutedLabel,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        week.label,
                        style: receiptHistoryText(
                          14,
                          FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    _CategoryAvatarStack(categories: week.categories),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Row(
                    children: [
                      Expanded(child: _SpendBar(pct: pct, zero: zero)),
                      const SizedBox(width: 8),
                      Text(
                        '${week.count} · RM${week.total.toStringAsFixed(2)}',
                        style: receiptHistoryText(
                          11,
                          FontWeight.w700,
                          color: ReceiptHistoryColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _WeekHeatmap(week: week),
                    Container(
                      margin: const EdgeInsets.only(left: 5, top: 2),
                      padding: const EdgeInsets.only(left: 17),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: ReceiptHistoryColors.timelineLine,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final day in week.days)
                            _DaySection(
                              day: day,
                              expanded: expandedDays.contains(day.date),
                              onToggle: () => onToggleDay(day),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 7-cell Mon–Sun spend heatmap for the expanded week, from the handoff's
/// `week.heatmap` — each cell's severity is relative to that week's own
/// busiest day.
class _WeekHeatmap extends StatelessWidget {
  const _WeekHeatmap({required this.week});

  final HistoryWeek week;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _widthFactor = 0.75;
  static const _gapShare = 7 / (7 * 24 + 6 * 7); // preserve handoff cell:gap ratio

  @override
  Widget build(BuildContext context) {
    final totalsByWeekday = <int, double>{
      for (final day in week.days) day.date.weekday: day.total,
    };
    final maxDayTotal = totalsByWeekday.values.isEmpty
        ? 0.0
        : totalsByWeekday.values.reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heatmapWidth = constraints.maxWidth * _widthFactor;
          final gap = heatmapWidth * _gapShare;

          return Align(
            alignment: Alignment.center,
            child: SizedBox(
              width: heatmapWidth,
              child: Row(
                children: [
                  for (var weekday = DateTime.monday;
                      weekday <= DateTime.sunday;
                      weekday++) ...[
                    if (weekday != DateTime.monday) SizedBox(width: gap),
                    Expanded(
                      child: _HeatCell(
                        letter: _letters[weekday - 1],
                        total: totalsByWeekday[weekday] ?? 0,
                        maxTotal: maxDayTotal,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeatCell extends StatelessWidget {
  const _HeatCell({required this.letter, required this.total, required this.maxTotal});

  final String letter;
  final double total;
  final double maxTotal;

  @override
  Widget build(BuildContext context) {
    final zero = total == 0;
    final pct = maxTotal > 0 ? total / maxTotal : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        return Column(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: receiptHistorySeverityColor(pct, zero: zero),
                borderRadius: BorderRadius.circular(size * 7 / 24),
              ),
            ),
            SizedBox(height: size * 4 / 24),
            Text(
              letter,
              style: receiptHistoryText(
                size * 10 / 24,
                FontWeight.w700,
                color: ReceiptHistoryColors.mutedLabel,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Spend-severity progress bar behind a week/day's total, from the handoff's
/// `week.barPct` / `week.barColor`.
class _SpendBar extends StatelessWidget {
  const _SpendBar({required this.pct, required this.zero});

  final double pct;
  final bool zero;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: ReceiptHistoryColors.divider,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: pct.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: receiptHistorySeverityColor(pct, zero: zero),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.expanded,
    required this.onToggle,
  });

  final HistoryDay day;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: ReceiptHistoryColors.chevronNested,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    day.label,
                    style: receiptHistoryText(
                      12.5,
                      FontWeight.w700,
                      color: const Color(0xFF5C5546),
                    ),
                  ),
                ),
                if (!expanded) ...[
                  _CategoryAvatarStack(categories: day.categories, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    '${day.items.length} · RM${day.total.toStringAsFixed(2)}',
                    style: receiptHistoryText(
                      11,
                      FontWeight.w600,
                      color: ReceiptHistoryColors.mutedLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.only(left: 15),
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: ReceiptHistoryColors.timelineLineNested,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < day.items.length; i++)
                        _HistoryItemRow(
                          tx: day.items[i],
                          isLast: i == day.items.length - 1,
                          nested: true,
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _HistoryItemRow extends StatelessWidget {
  const _HistoryItemRow({
    required this.tx,
    required this.isLast,
    this.nested = false,
  });

  final TransactionView tx;
  final bool isLast;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final palette = receiptPaletteForCategory(tx.effectiveCategory);
    final timeLabel = DateFormat('h:mm a').format(tx.occurredAt);
    final amountText =
        tx.amountMyr != null ? 'RM${tx.amountMyr!.toStringAsFixed(2)}' : '—';
    final dotOffset = nested ? -21.0 : -23.0;
    final dotSize =
        nested ? 8.0 : ReceiptHistoryLayout.timelineDotSize;
    final iconSize = nested ? 30.0 : ReceiptHistoryLayout.categoryIconSize;
    final iconEmojiSize = nested ? 15.0 : 18.0;

    return InkWell(
      onTap: () => context.pushNamed('tx-detail', pathParameters: {'id': tx.id}),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: nested ? 11 : 13),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    color: nested
                        ? ReceiptHistoryColors.rowBorderNested
                        : ReceiptHistoryColors.divider,
                  ),
                ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: dotOffset,
              top: 0,
              bottom: 0,
              child: Center(
                child: Container(
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: palette.acc,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.tile,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    palette.emoji,
                    style: TextStyle(fontSize: iconEmojiSize),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tx.displayPlace,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: receiptHistoryText(
                          nested ? 13.5 : 14.5,
                          FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${tx.effectiveCategory} · $timeLabel',
                        style: receiptHistoryText(
                          11.5,
                          FontWeight.w600,
                          color: ReceiptHistoryColors.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  amountText,
                  style: receiptHistoryText(nested ? 13.5 : 14.5, FontWeight.w800),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Up-to-3 overlapping category-icon avatars (accent-tint circle + emoji)
/// plus a "+N" overflow bubble, from the handoff's `week.icons`/`day.icons`
/// stack — used for both the week header and a collapsed day row.
class _CategoryAvatarStack extends StatelessWidget {
  const _CategoryAvatarStack({required this.categories, this.size = 18});

  final List<String> categories;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final visible = categories.take(3).toList();
    final overflow = categories.length - visible.length;
    final step = size * 0.65;
    final slots = visible.length + (overflow > 0 ? 1 : 0);

    return SizedBox(
      width: size + step * (slots - 1),
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (overflow > 0)
            Positioned(
              left: visible.length * step,
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ReceiptHistoryColors.timelineLine.withValues(alpha: 0.75),
                  shape: BoxShape.circle,
                  border: Border.all(color: ReceiptHistoryColors.card, width: 1.5),
                ),
                child: Text(
                  '+$overflow',
                  style: receiptHistoryText(
                    size * 0.42,
                    FontWeight.w800,
                    color: ReceiptHistoryColors.mutedText,
                  ),
                ),
              ),
            ),
          for (var i = visible.length - 1; i >= 0; i--)
            Positioned(
              left: i * step,
              child: _AvatarDot(category: visible[i], size: size),
            ),
        ],
      ),
    );
  }
}

class _AvatarDot extends StatelessWidget {
  const _AvatarDot({required this.category, required this.size});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = receiptPaletteForCategory(category);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.acc,
        shape: BoxShape.circle,
        border: Border.all(color: ReceiptHistoryColors.card, width: 1.5),
      ),
      child: Text(palette.emoji, style: TextStyle(fontSize: size * 0.5, height: 1)),
    );
  }
}
