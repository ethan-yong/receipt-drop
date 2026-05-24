import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/platform/platform_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/puggy_primary_button.dart';
import '../../widgets/receipt_thumbnail.dart';
import 'receipt_ingest_draft.dart';

/// Save sheet after receipt ingest (manual upload or share).
class ShareSaveSheet extends StatefulWidget {
  const ShareSaveSheet({
    super.key,
    required this.draft,
    required this.onSave,
    required this.onCancel,
  });

  final ReceiptIngestDraft draft;
  final Future<void> Function(double? amount, ReceiptIngestDraft draft) onSave;
  final Future<void> Function(ReceiptIngestDraft draft) onCancel;

  /// Returns true if the user saved.
  static Future<bool> show(
    BuildContext context, {
    required ReceiptIngestDraft draft,
    required Future<void> Function(double? amount, ReceiptIngestDraft draft)
        onSave,
    required Future<void> Function(ReceiptIngestDraft draft) onCancel,
  }) async {
    final result = await AdaptiveSheet.showForm<bool>(
      context: context,
      isScrollControlled: true,
      child: ShareSaveSheet(
        draft: draft,
        onSave: onSave,
        onCancel: onCancel,
      ),
    );
    return result ?? false;
  }

  @override
  State<ShareSaveSheet> createState() => _ShareSaveSheetState();
}

class _ShareSaveSheetState extends State<ShareSaveSheet> {
  late final TextEditingController _amountController;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final amount = widget.draft.amountMyr;
    _amountController = TextEditingController(
      text: amount != null ? amount.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double? _parseAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _save() async {
    final amount = _parseAmount();
    if (amount == null || amount <= 0) {
      PlatformFeedback.showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(amount, widget.draft);
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
          child: ReceiptThumbnail(
            size: 72,
            radius: 12,
            localPath: widget.draft.localFilePath.startsWith('web:')
                ? null
                : widget.draft.localFilePath,
            thumbnailBytes: widget.draft.thumbnailBytes,
          ),
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
        const SizedBox(height: AppSpacing.lg),
        AmountField(controller: _amountController),
        const SizedBox(height: AppSpacing.lg),
      ],
    );

    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PuggyPrimaryButton(
          label: 'Save',
          onPressed: _saving ? null : _save,
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
