import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/receipt_drop_primary_button.dart';
import '../../widgets/skeleton.dart';

/// Queue of receipts that OCR couldn't confidently read: one-tap confirm
/// releases them back into the normal pipeline instead of losing them.
class ReceiptReviewScreen extends StatelessWidget {
  const ReceiptReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        backgroundColor: AppColors.scaffold,
        title: const Text('Review receipts'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<TransactionView>>(
          stream: AppServices.transactions.watchNeedsReview(),
          builder: (context, snapshot) {
            final rows = snapshot.data;
            if (rows == null) {
              return const _ReviewListSkeleton();
            }
            if (rows.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: AppColors.primaryGreen,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Nothing to review.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              itemCount: rows.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _ReviewCard(
                // Key by id so controllers reset correctly as rows leave the queue.
                key: ValueKey(rows[i].id),
                tx: rows[i],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReviewListSkeleton extends StatelessWidget {
  const _ReviewListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            const _ReviewCardSkeleton(),
          ],
        ],
      ),
    );
  }
}

class _ReviewCardSkeleton extends StatelessWidget {
  const _ReviewCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 48, height: 64, radius: 12),
              SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 140, height: 16),
                    SizedBox(height: 6),
                    SkeletonBox(width: 100, height: 12),
                  ],
                ),
              ),
              SkeletonBox(width: 64, height: 22, radius: 11),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          SkeletonBox(width: double.infinity, height: 44, radius: 12),
          SizedBox(height: AppSpacing.sm),
          SkeletonBox(width: double.infinity, height: 44, radius: 20),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatefulWidget {
  const _ReviewCard({super.key, required this.tx});

  final TransactionView tx;

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  late final TextEditingController _amountController;
  var _confirming = false;

  @override
  void initState() {
    super.initState();
    final amount = widget.tx.amountMyr;
    _amountController = TextEditingController(
      text: amount != null ? amount.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final raw = _amountController.text.trim().replaceAll(',', '');
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      PlatformFeedback.showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _confirming = true);
    try {
      await AppServices.transactions.confirmReview(widget.tx.id, amount);
      PlatformFeedback.mediumTap();
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.tx;
    final thumbPath = tx.localThumbnailPath;
    final rawText = tx.rawOcrText;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (thumbPath != null && !thumbPath.startsWith('web:'))
                ClipRRect(
                  borderRadius: AppSpacing.chipBorderRadius,
                  child: Image.file(
                    File(thumbPath),
                    width: 48,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 48,
                      height: 64,
                      child: Icon(Icons.receipt_long, size: 24),
                    ),
                  ),
                )
              else
                const SizedBox(
                  width: 48,
                  height: 64,
                  child: Icon(Icons.receipt_long, size: 24),
                ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx.displayPlace,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tx.amountMyr != null
                          ? 'Best guess: RM ${tx.amountMyr!.toStringAsFixed(2)}'
                          : 'No amount detected',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _ConfidenceChip(confidence: tx.ocrConfidence),
            ],
          ),
          if (rawText != null && rawText.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding:
                    const EdgeInsets.only(bottom: AppSpacing.sm),
                title: Text(
                  'Scanned text',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      rawText,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          AmountField(controller: _amountController),
          const SizedBox(height: AppSpacing.sm),
          ReceiptDropPrimaryButton(
            label: 'Confirm',
            onPressed: _confirming ? null : _confirm,
          ),
        ],
      ),
    );
  }
}

class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final pct = confidence != null ? (confidence! * 100).round() : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.badgePendingBg,
        borderRadius: AppSpacing.chipBorderRadius,
      ),
      child: Text(
        pct != null ? '$pct% sure' : 'unreadable',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.badgePendingText,
            ),
      ),
    );
  }
}
