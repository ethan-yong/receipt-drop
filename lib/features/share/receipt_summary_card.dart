import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/platform/platform_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/receipt_drop_primary_button.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_summary_view_model.dart';

/// One-glance receipt preview shown after OCR parsing, before the save sheet.
///
/// Returns `true` if the user wants to proceed (either CTA), `false` if
/// they cancelled or dismissed the sheet.
class ReceiptSummaryCard extends StatelessWidget {
  const ReceiptSummaryCard({super.key, required this.draft});

  final ReceiptIngestDraft draft;

  static Future<bool> show(
    BuildContext context, {
    required ReceiptIngestDraft draft,
  }) async {
    final result = await AdaptiveSheet.showForm<bool>(
      context: context,
      isScrollControlled: true,
      child: ReceiptSummaryCard(draft: draft),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final vm = ReceiptSummaryViewModel.from(draft);

    if (PlatformUtils.isCupertino) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Body(vm: vm, draft: draft),
            _Actions(vm: vm),
          ],
        ),
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.55,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: _Body(vm: vm, draft: draft),
            ),
          ),
          Material(
            elevation: 8,
            color: AppColors.cardSurface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: _Actions(vm: vm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.vm, required this.draft});

  final ReceiptSummaryViewModel vm;
  final ReceiptIngestDraft draft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CategoryChip(label: vm.categoryLabel),
            const Spacer(),
            if (vm.lineItemCount > 0)
              Text(
                '${vm.lineItemCount} item${vm.lineItemCount == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          vm.merchantDisplay,
          style: theme.textTheme.displaySmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          vm.amountDisplay,
          style: theme.textTheme.displayLarge?.copyWith(
            color: vm.hasAmount ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
        if (vm.isLowConfidence) ...[
          const SizedBox(height: AppSpacing.sm),
          _WarningBanner(needsAmount: draft.needsAmount),
        ],
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.needsAmount});

  final bool needsAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.badgePendingBg,
        borderRadius: AppSpacing.chipBorderRadius,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: AppColors.badgePendingText,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              needsAmount
                  ? "We couldn't read the amount — enter it below."
                  : "Double-check this amount — we're not fully sure.",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.badgePendingText,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.vm});

  final ReceiptSummaryViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReceiptDropPrimaryButton(
          label: vm.hasAmount ? 'Looks good' : 'Edit details',
          onPressed: () => Navigator.pop(context, true),
        ),
        if (vm.hasAmount)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Edit details'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
