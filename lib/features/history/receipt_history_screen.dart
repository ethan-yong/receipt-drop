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
    required this.expandedDays,
    required this.onToggle,
    required this.onToggleDay,
  });

  final HistoryWeek week;
  final bool expanded;
  final Set<DateTime> expandedDays;
  final VoidCallback onToggle;
  final ValueChanged<HistoryDay> onToggleDay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: ReceiptHistoryColors.mutedLabel,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        week.label,
                        style: receiptHistoryText(
                          14,
                          FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (!expanded) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${week.count} receipts · RM${week.total.toStringAsFixed(2)}',
                              style: receiptHistoryText(
                                11.5,
                                FontWeight.w600,
                                color: ReceiptHistoryColors.mutedText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              week.categories
                                  .map((c) => receiptPaletteForCategory(c).emoji)
                                  .join(' '),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ],
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
              : Container(
                  margin: const EdgeInsets.only(left: 5, top: 6),
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
        ),
      ],
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
                if (!expanded)
                  Text(
                    '${day.items.length} · RM${day.total.toStringAsFixed(2)}',
                    style: receiptHistoryText(
                      11,
                      FontWeight.w600,
                      color: ReceiptHistoryColors.mutedLabel,
                    ),
                  ),
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
                    border: Border.all(color: ReceiptHistoryColors.card, width: 2.5),
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
