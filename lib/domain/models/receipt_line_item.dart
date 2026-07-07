/// A single extracted item + price row from receipt OCR text.
class ReceiptLineItem {
  const ReceiptLineItem({
    required this.name,
    required this.priceMyr,
    this.quantity,
    this.confidence,
    this.lineIndex,
  });

  final String name;
  final double priceMyr;
  final int? quantity; // when detectable, e.g. "2 x"
  final double? confidence; // parser confidence for this row
  final int? lineIndex; // source line in OCR text (debug / UI)

  /// "3× Teh O Limau Ais" when a quantity above one was detected, else just
  /// the name (a qty of 1 adds no information on screen).
  String get displayLabel =>
      quantity != null && quantity! > 1 ? '$quantity× $name' : name;

  /// The row's printed price, e.g. "RM 8.70". On Malaysian receipts this is
  /// the line total, not a unit price.
  String get priceDisplay => 'RM ${priceMyr.toStringAsFixed(2)}';

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceMyr': priceMyr,
        if (quantity != null) 'quantity': quantity,
        if (confidence != null) 'confidence': confidence,
      };
}
