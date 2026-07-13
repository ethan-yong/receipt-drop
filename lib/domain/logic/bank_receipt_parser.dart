/// Provider-specific receipt parsers for structured bank/wallet payment
/// screenshots. These bypass the heuristic extractor and LLM pipeline entirely
/// when a known provider is detected and required fields are present.
///
/// Returns [BankParseResult] which [receipt_parse_pipeline.dart] assembles into
/// a full [ReceiptParseResult]. Returns `null` for unknown providers or when
/// required fields (amount or merchant) are missing — the caller falls through
/// to the existing heuristic+LLM pipeline.

enum BankProvider { maybank, cimb, tng, unknown }

/// Lightweight result from a provider-specific parse. Assembled into a full
/// ReceiptParseResult by receipt_parse_pipeline.dart.
class BankParseResult {
  const BankParseResult({
    required this.provider,
    required this.amountMyr,
    required this.merchantRaw,
    required this.category,
  });

  final BankProvider provider;
  final double amountMyr;
  final String merchantRaw;

  /// 'Transfer' for bank-to-bank/person payments; 'Payment' for wallet
  /// merchant payments (TNG).
  final String category;
}

/// Detects the bank/wallet provider from OCR text using case-insensitive
/// keyword matching. First match wins — order matters (more specific before
/// more ambiguous: e.g. check Maybank before generic 'bank').
BankProvider detectBankProvider(String text) {
  final t = text.toLowerCase();
  if (t.contains('maybank') || t.contains('mae') || t.contains('maybank2u')) {
    return BankProvider.maybank;
  }
  if (t.contains('cimb') || t.contains('octo')) {
    return BankProvider.cimb;
  }
  if (t.contains("touch 'n go") ||
      t.contains('touch n go') ||
      t.contains('tng') ||
      t.contains('ewallet')) {
    return BankProvider.tng;
  }
  return BankProvider.unknown;
}

// Shared: RM 120.00 / RM120.00 / RM 1,234.56
final _amountRx = RegExp(r'RM\s*([\d,]+\.\d{2})', caseSensitive: false);

double? _parseAmount(String text) {
  final m = _amountRx.firstMatch(text);
  if (m == null) return null;
  return double.tryParse(m.group(1)!.replaceAll(',', ''));
}

BankParseResult? _parseMaybank(String text) {
  final amount = _parseAmount(text);
  if (amount == null) return null;
  final m = RegExp(r'To:\s*(.+)', caseSensitive: false).firstMatch(text);
  final merchant = m?.group(1)?.trim();
  if (merchant == null || merchant.isEmpty) return null;
  return BankParseResult(
    provider: BankProvider.maybank,
    amountMyr: amount,
    merchantRaw: merchant,
    category: 'Transfer',
  );
}

BankParseResult? _parseCimb(String text) {
  final amount = _parseAmount(text);
  if (amount == null) return null;
  // "Recipient Name:" preferred; fall back to "To:"
  final m = RegExp(
    r'(?:Recipient Name|To):\s*(.+)',
    caseSensitive: false,
  ).firstMatch(text);
  final merchant = m?.group(1)?.trim();
  if (merchant == null || merchant.isEmpty) return null;
  return BankParseResult(
    provider: BankProvider.cimb,
    amountMyr: amount,
    merchantRaw: merchant,
    category: 'Transfer',
  );
}

BankParseResult? _parseTng(String text) {
  final amount = _parseAmount(text);
  if (amount == null) return null;
  // "Merchant:" preferred; fall back to "Paid to:"
  final m = RegExp(
    r'(?:Merchant|Paid to):\s*(.+)',
    caseSensitive: false,
  ).firstMatch(text);
  final merchant = m?.group(1)?.trim();
  if (merchant == null || merchant.isEmpty) return null;
  return BankParseResult(
    provider: BankProvider.tng,
    amountMyr: amount,
    merchantRaw: merchant,
    category: 'Payment',
  );
}

/// Entry point called from parseReceiptOcrText(). Returns `null` for unknown
/// providers or when required fields are missing — the caller falls through to
/// the full heuristic+LLM pipeline.
BankParseResult? tryParseBankReceipt(String text) =>
    switch (detectBankProvider(text)) {
      BankProvider.maybank => _parseMaybank(text),
      BankProvider.cimb => _parseCimb(text),
      BankProvider.tng => _parseTng(text),
      BankProvider.unknown => null,
    };
