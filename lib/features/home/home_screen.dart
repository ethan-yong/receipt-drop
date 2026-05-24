import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/logic/dashboard_aggregates.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/adaptive_sync_banner.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/grouped_transaction_list.dart';
import '../../widgets/platform_refresh_scroll_view.dart';
import '../../widgets/share_coach_mark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _showCoachMark = AppPrefs.shareCoachMarkPending && !AppPrefs.shareCoachMarkSeen;

  Future<void> _refresh() async {
    await AppServices.transactions.retryStuckSync();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }

  Future<void> _deleteTransaction(TransactionView tx) async {
    await AppServices.transactions.deleteTransaction(tx.id);
    if (mounted) {
      PlatformFeedback.showMessage(context, 'Receipt deleted');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text(
          'PuggyBank',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.primaryGreen,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: StreamBuilder<List<TransactionView>>(
        stream: AppServices.transactions.watchAll(),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) {
            return const EmptyState(
              title: 'No receipts yet',
              subtitle:
                  'Share a receipt from your bank app or tap + to get started.',
            );
          }

          final stuck = rows.where((t) => t.isStuckSync).length;
          final now = DateTime.now();
          final groups = <String, List<TransactionView>>{};
          for (final t in rows) {
            final label = dayGroupLabel(t.occurredAt, now);
            groups.putIfAbsent(label, () => []).add(t);
          }

          return Column(
            children: [
              if (_showCoachMark)
                ShareCoachMark(
                  onDismiss: () => setState(() => _showCoachMark = false),
                ),
              AdaptiveSyncBanner(
                stuckCount: stuck,
                onRetry: _refresh,
              ),
              Expanded(
                child: PlatformRefreshScrollView(
                  onRefresh: _refresh,
                  slivers: [
                    SliverToBoxAdapter(
                      child: GroupedTransactionList(
                        groups: groups,
                        onTap: (tx) => context.pushNamed(
                          'tx-detail',
                          pathParameters: {'id': tx.id},
                        ),
                        onDelete: _deleteTransaction,
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
