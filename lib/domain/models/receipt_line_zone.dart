/// Zone label for one OCR line (index-aligned with raw `ocrText.split('\n')`).
enum ReceiptLineZone {
  header,
  body,
  footer,
  ambiguous,
}

/// Per-line zone labels plus a reliability flag. When [isReliable] is false,
/// consumers must behave exactly as if zones were never supplied.
class ReceiptLayoutAnalysis {
  const ReceiptLayoutAnalysis({
    required this.zones,
    required this.isReliable,
  });

  final List<ReceiptLineZone> zones;
  final bool isReliable;

  ReceiptLineZone? zoneAt(int lineIndex) {
    if (!isReliable || lineIndex < 0 || lineIndex >= zones.length) {
      return null;
    }
    return zones[lineIndex];
  }
}
