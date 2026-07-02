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

  Map<String, dynamic> toJson() => {
        'name': name,
        'priceMyr': priceMyr,
        if (quantity != null) 'quantity': quantity,
        if (confidence != null) 'confidence': confidence,
      };
}
