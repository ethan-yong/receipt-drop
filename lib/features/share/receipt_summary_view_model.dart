import 'receipt_ingest_draft.dart';

/// Display-ready representation of a parsed receipt, derived from
/// [ReceiptIngestDraft]. Contains no raw OCR data — only cleaned strings
/// safe to show directly in the Smart Summary Card.
class ReceiptSummaryViewModel {
  const ReceiptSummaryViewModel({
    required this.merchantDisplay,
    required this.amountDisplay,
    required this.categoryLabel,
    required this.hasAmount,
    required this.isLowConfidence,
    required this.lineItemCount,
  });

  final String merchantDisplay;
  final String amountDisplay;
  final String categoryLabel;
  final bool hasAmount;
  final bool isLowConfidence;
  final int lineItemCount;

  factory ReceiptSummaryViewModel.from(ReceiptIngestDraft draft) {
    return ReceiptSummaryViewModel(
      merchantDisplay: _cleanMerchant(draft.merchantRaw),
      amountDisplay: draft.amountMyr != null
          ? 'RM ${draft.amountMyr!.toStringAsFixed(2)}'
          : '–',
      categoryLabel: draft.categoryGuess,
      hasAmount: !draft.needsAmount && draft.amountMyr != null,
      isLowConfidence: draft.needsAmount || draft.lowConfidence,
      lineItemCount: draft.lineItems.length,
    );
  }

  /// Title-cases and strips trailing Malaysian/generic business suffixes
  /// (SDN BHD, PLT, BHD, etc.) from a raw OCR merchant string.
  static String _cleanMerchant(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Unknown merchant';
    var s = raw.trim();
    s = s.replaceAll(
      RegExp(
        r'\s+(SDN\.?\s*BHD\.?|PLT\.?|BHD\.?|PTE\.?\s*LTD\.?|SDN\.?|INC\.?|CORP\.?)\s*$',
        caseSensitive: false,
      ),
      '',
    ).trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return raw.trim();
    return s.split(' ').map((w) {
      if (w.isEmpty) return '';
      return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
    }).join(' ');
  }
}
