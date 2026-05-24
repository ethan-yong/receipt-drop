import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../domain/models/transaction_view.dart';
import 'category_chip.dart';
import 'receipt_thumbnail.dart';
import 'status_badge.dart';

class TransactionListTile extends StatelessWidget {
  const TransactionListTile({
    super.key,
    required this.transaction,
    required this.onTap,
    this.grouped = false,
  });

  final TransactionView transaction;
  final VoidCallback onTap;
  final bool grouped;

  @override
  Widget build(BuildContext context) {
    final amount = transaction.amountMyr;
    final amountText = amount != null
        ? 'RM ${NumberFormat('#,##0.00').format(amount)}'
        : '—';

    return Material(
      color: grouped ? Colors.transparent : AppColors.cardSurface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: grouped ? AppSpacing.md : AppSpacing.md,
            vertical: AppSpacing.sm + 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReceiptThumbnail(
                localPath: transaction.localThumbnailPath,
                thumbnailBytes: transaction.thumbnailBytes,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.displayPlace,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        CategoryChip(label: transaction.effectiveCategory),
                        if (transaction.isPendingSync) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            kind: TransactionBadgeKind.pendingSync,
                          ),
                        ],
                        if (transaction.needsAmount) ...[
                          const SizedBox(width: 6),
                          const StatusBadge(
                            kind: TransactionBadgeKind.needsAmount,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                amountText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: transaction.needsAmount
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
