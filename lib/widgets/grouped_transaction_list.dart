import 'package:flutter/material.dart';

import '../core/platform/platform_utils.dart';
import '../core/theme/app_theme.dart';
import '../domain/models/transaction_view.dart';
import 'section_header.dart';
import 'transaction_list_tile.dart';

/// Grouped receipt list with platform-native row styling.
class GroupedTransactionList extends StatelessWidget {
  const GroupedTransactionList({
    super.key,
    required this.groups,
    required this.onTap,
    this.onDelete,
  });

  final Map<String, List<TransactionView>> groups;
  final void Function(TransactionView tx) onTap;
  final void Function(TransactionView tx)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          SectionHeader(title: entry.key),
          if (PlatformUtils.isCupertino)
            _CupertinoGroup(
              transactions: entry.value,
              onTap: onTap,
              onDelete: onDelete,
            )
          else
            _AndroidGroup(
              transactions: entry.value,
              onTap: onTap,
              onDelete: onDelete,
            ),
        ],
      ],
    );
  }
}

class _CupertinoGroup extends StatelessWidget {
  const _CupertinoGroup({
    required this.transactions,
    required this.onTap,
    this.onDelete,
  });

  final List<TransactionView> transactions;
  final void Function(TransactionView tx) onTap;
  final void Function(TransactionView tx)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            for (var i = 0; i < transactions.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, indent: 72, color: AppColors.divider),
              _maybeDismissible(
                tx: transactions[i],
                child: TransactionListTile(
                  transaction: transactions[i],
                  grouped: true,
                  onTap: () => onTap(transactions[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _maybeDismissible({
    required TransactionView tx,
    required Widget child,
  }) {
    if (onDelete == null) return child;
    return Dismissible(
      key: ValueKey(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.destructive,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete!(tx),
      child: child,
    );
  }
}

class _AndroidGroup extends StatelessWidget {
  const _AndroidGroup({
    required this.transactions,
    required this.onTap,
    this.onDelete,
  });

  final List<TransactionView> transactions;
  final void Function(TransactionView tx) onTap;
  final void Function(TransactionView tx)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < transactions.length; i++)
          _maybeDismissible(
            tx: transactions[i],
            child: Column(
              children: [
                TransactionListTile(
                  transaction: transactions[i],
                  grouped: true,
                  onTap: () => onTap(transactions[i]),
                ),
                if (i < transactions.length - 1)
                  const Divider(
                    height: 1,
                    indent: AppSpacing.md + 56,
                    endIndent: AppSpacing.md,
                    color: AppColors.divider,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _maybeDismissible({
    required TransactionView tx,
    required Widget child,
  }) {
    if (onDelete == null) return child;
    return Dismissible(
      key: ValueKey(tx.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.destructive,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete!(tx),
      child: child,
    );
  }
}
