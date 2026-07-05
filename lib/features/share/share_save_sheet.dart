import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/platform/platform_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/logic/rm_amount_parser.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/receipt_drop_primary_button.dart';
import '../../widgets/receipt_strip.dart';
import 'receipt_ingest_draft.dart';

/// Save sheet after receipt ingest (manual upload or share).
class ShareSaveSheet extends StatefulWidget {
  const ShareSaveSheet({
    super.key,
    required this.draft,
    required this.categories,
    required this.onSave,
    required this.onCancel,
    this.onSaveForLater,
  });

  final ReceiptIngestDraft draft;

  /// Category rules used to populate the inline category picker.
  final CategoryConfig categories;

  final Future<void> Function(
    double? amount,
    ReceiptIngestDraft draft,
    ImpactLevel impact,
  ) onSave;
  final Future<void> Function(ReceiptIngestDraft draft) onCancel;

  /// Parks the receipt in the review queue instead of confirming now.
  /// Offered only for needs-amount / low-confidence drafts.
  final Future<void> Function(ReceiptIngestDraft draft)? onSaveForLater;

  /// Returns true if the user saved.
  static Future<bool> show(
    BuildContext context, {
    required ReceiptIngestDraft draft,
    required CategoryConfig categories,
    required Future<void> Function(
      double? amount,
      ReceiptIngestDraft draft,
      ImpactLevel impact,
    ) onSave,
    required Future<void> Function(ReceiptIngestDraft draft) onCancel,
    Future<void> Function(ReceiptIngestDraft draft)? onSaveForLater,
  }) async {
    final result = await AdaptiveSheet.showForm<bool>(
      context: context,
      isScrollControlled: true,
      child: ShareSaveSheet(
        draft: draft,
        categories: categories,
        onSave: onSave,
        onCancel: onCancel,
        onSaveForLater: onSaveForLater,
      ),
    );
    return result ?? false;
  }

  @override
  State<ShareSaveSheet> createState() => _ShareSaveSheetState();
}

class _ShareSaveSheetState extends State<ShareSaveSheet> {
  late final TextEditingController _amountController;
  ImpactLevel? _impactOverride;
  String? _categoryOverride;
  var _saving = false;

  // Draft carries the combined-confidence verdict from the parse pipeline;
  // the raw ocrConfidence threshold is only the fallback for older drafts.
  bool get _lowConfidence =>
      widget.draft.lowConfidence ||
      (!widget.draft.needsAmount &&
          (widget.draft.ocrConfidence ?? 0) < lowOcrConfidenceThreshold);

  bool get _canSaveForLater =>
      widget.onSaveForLater != null &&
      (widget.draft.needsAmount || _lowConfidence);

  @override
  void initState() {
    super.initState();
    final amount = widget.draft.amountMyr;
    _amountController = TextEditingController(
      text: amount != null ? amount.toStringAsFixed(2) : '',
    );
    if (_lowConfidence) {
      _amountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _amountController.text.length,
      );
    }
    _amountController.addListener(_onAmountChanged);
  }

  void _onAmountChanged() => setState(() {});

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  ImpactLevel get _effectiveImpact =>
      _impactOverride ?? deriveImpactLevel(_parseAmount());

  Future<void> _save() async {
    final amount = _parseAmount();
    if (amount == null || amount <= 0) {
      PlatformFeedback.showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    final draft = _categoryOverride != null
        ? widget.draft.copyWith(categoryUser: _categoryOverride)
        : widget.draft;
    try {
      await widget.onSave(amount, draft, _effectiveImpact);
      if (mounted) {
        PlatformFeedback.mediumTap();
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    await widget.onCancel(widget.draft);
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _saveForLater() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveForLater!(widget.draft);
      if (mounted) {
        PlatformFeedback.mediumTap();
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.draft.needsAmount
        ? 'Enter amount'
        : 'Receipt detected';

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!PlatformUtils.isCupertino) ...[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        Center(
          child: ReceiptStrip(impact: _effectiveImpact),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (widget.draft.merchantRaw != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.draft.merchantRaw!,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
        if (_lowConfidence) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
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
                    "Double-check this amount — we're not fully sure we read it correctly.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.badgePendingText,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        AmountField(controller: _amountController),
        const SizedBox(height: AppSpacing.md),
        Text('Category', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        _CategoryDropdown(
          value: _categoryOverride ?? widget.draft.categoryGuess,
          categories: widget.categories,
          onChanged: (v) => setState(() => _categoryOverride = v),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Impact', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final level in ImpactLevel.values) ...[
              if (level != ImpactLevel.values.first)
                const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ImpactChip(
                  level: level,
                  selected: _effectiveImpact == level,
                  onTap: () => setState(() => _impactOverride = level),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReceiptDropPrimaryButton(
          label: 'Save',
          onPressed: _saving ? null : _save,
        ),
        if (_canSaveForLater)
          TextButton(
            onPressed: _saving ? null : _saveForLater,
            child: const Text('Save for later'),
          ),
        TextButton(
          onPressed: _saving ? null : _cancel,
          child: const Text('Cancel'),
        ),
      ],
    );

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
          children: [
            content,
            actions,
          ],
        ),
      );
    }

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: content,
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
                child: actions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String value;
  final CategoryConfig categories;
  final ValueChanged<String?> onChanged;

  List<String> get _items => {
        ...categories.rules.map((r) => r.category),
        categories.defaultCategory,
      }.toList();

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final safeValue = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      value: safeValue,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        isDense: true,
      ),
      items: items.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: onChanged,
    );
  }
}

class _ImpactChip extends StatelessWidget {
  const _ImpactChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final ImpactLevel level;
  final bool selected;
  final VoidCallback onTap;

  Color get _color {
    switch (level) {
      case ImpactLevel.low:
        return AppColors.impactLow;
      case ImpactLevel.med:
        return AppColors.impactMed;
      case ImpactLevel.high:
        return AppColors.impactHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.chipBorderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _color : AppColors.cardSurface,
          borderRadius: AppSpacing.chipBorderRadius,
          border: Border.all(
            color: selected ? _color : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          level.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
