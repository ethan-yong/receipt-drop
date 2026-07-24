/// A predicted-vs-confirmed diff captured at the exact point in
/// `receipt_confirm_sheet.dart` where the OCR/LLM prediction and the user's
/// confirmed value are both still in scope, before the save payload
/// overwrites the original. See
/// `docs/plans/2026-07-23-feedback-learning-system.md`.
///
/// This is the single source-of-truth event every learning surface (merchant
/// alias write-back, category preference, OCR misread patterns) derives
/// from — nothing here mutates any of those surfaces directly; it's just the
/// raw diff, synced up and consumed server-side (or by a later client read)
/// per surface.
class FieldCorrection {
  const FieldCorrection({
    required this.field,
    required this.predictedValue,
    required this.confirmedValue,
    this.merchantRaw,
    this.confidence,
    this.correctionType,
    this.lineItemIndex,
  });

  /// One of [fieldMerchant], [fieldAmount], [fieldCategory],
  /// [fieldLineItemPrice].
  final String field;

  /// The OCR/LLM/heuristic prediction, as a string (numeric fields are
  /// formatted with [_formatAmount] so both sides compare like-for-like).
  final String predictedValue;

  /// The value the user actually confirmed/typed/selected.
  final String confirmedValue;

  /// Merchant text this correction is associated with, regardless of
  /// [field] — always the *predicted* merchant name at capture time. Lets a
  /// category or amount correction still be attributed to a merchant for
  /// keying purposes without re-deriving it downstream.
  final String? merchantRaw;

  /// The predicted value's own extraction/OCR confidence, when known.
  final double? confidence;

  /// For [fieldMerchant] only: [correctionTypeFreeText] or
  /// [correctionTypeUserLocked] — a deliberate picker pick is a much
  /// stronger signal than a quick text edit (see Decision Logic in the
  /// feature plan).
  final String? correctionType;

  /// For [fieldLineItemPrice] only: which item index changed.
  final int? lineItemIndex;

  static const fieldMerchant = 'merchant';
  static const fieldAmount = 'amount';
  static const fieldCategory = 'category';
  static const fieldLineItemPrice = 'line_item_price';

  static const correctionTypeFreeText = 'free_text';
  static const correctionTypeUserLocked = 'user_locked';

  /// Formats a numeric amount the same way on both sides of a correction
  /// (predicted vs. confirmed) so downstream character-alignment (misread
  /// pattern extraction) compares like-for-like strings.
  static String formatAmount(double value) => value.toStringAsFixed(2);

  Map<String, dynamic> toJson() => {
        'field': field,
        'predictedValue': predictedValue,
        'confirmedValue': confirmedValue,
        if (merchantRaw != null) 'merchantRaw': merchantRaw,
        if (confidence != null) 'confidence': confidence,
        if (correctionType != null) 'correctionType': correctionType,
        if (lineItemIndex != null) 'lineItemIndex': lineItemIndex,
      };

  static FieldCorrection? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final field = json['field'];
    final predicted = json['predictedValue'];
    final confirmed = json['confirmedValue'];
    if (field is! String || predicted is! String || confirmed is! String) {
      return null;
    }
    final confidence = json['confidence'];
    final lineItemIndex = json['lineItemIndex'];
    return FieldCorrection(
      field: field,
      predictedValue: predicted,
      confirmedValue: confirmed,
      merchantRaw: json['merchantRaw'] as String?,
      confidence: confidence is num ? confidence.toDouble() : null,
      correctionType: json['correctionType'] as String?,
      lineItemIndex: lineItemIndex is num ? lineItemIndex.toInt() : null,
    );
  }
}
