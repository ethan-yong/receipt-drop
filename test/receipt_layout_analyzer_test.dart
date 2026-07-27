import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/receipt_layout_analyzer.dart';
import 'package:receipt_drop/domain/logic/receipt_line_item_extractor.dart';
import 'package:receipt_drop/domain/models/ocr_line.dart';
import 'package:receipt_drop/domain/models/receipt_line_zone.dart';

List<OcrLine> _linesForText(String ocrText, {double left = 0.05, double width = 0.4}) {
  return [
    for (final _ in ocrText.split('\n'))
      OcrLine(text: '', heightRatio: 0.02, leftRatio: left, widthRatio: width),
  ];
}

List<OcrLine> _linesWithTexts(List<String> texts, {List<double>? heightRatios}) {
  return [
    for (var i = 0; i < texts.length; i++)
      OcrLine(
        text: texts[i],
        heightRatio: heightRatios != null && i < heightRatios.length
            ? heightRatios[i]
            : 0.02,
        leftRatio: 0.05,
        widthRatio: 0.4,
      ),
  ];
}

void main() {
  test('returns null when ocrLines is null or length mismatches ocrText', () {
    const ocr = 'A\nB\nC\nD';
    expect(analyzeReceiptLayout(ocr, null), isNull);
    expect(
      analyzeReceiptLayout(ocr, [const OcrLine(text: 'A', heightRatio: 0.1)]),
      isNull,
    );
  });

  test('returns null for receipts below minimum line count', () {
    const ocr = 'SHOP\nRM 3.00';
    final lines = _linesForText(ocr);
    expect(analyzeReceiptLayout(ocr, lines), isNull);
  });

  test('zone indices align with raw ocrText line split', () {
    const ocr =
        'RESTORAN MAJU\n'
        'Table 5\n'
        'Kopitiam Fried Rice  RM 12.00\n'
        'Teh Tarik           RM 3.00\n'
        'TOTAL               RM 15.00';
    final texts = ocr.split('\n');
    final lines = _linesWithTexts(texts);
    final layout = analyzeReceiptLayout(ocr, lines);
    expect(layout, isNotNull);
    expect(layout!.zones.length, texts.length);
    expect(layout.zoneAt(0), ReceiptLineZone.header);
    expect(layout.zoneAt(2), ReceiptLineZone.body);
    expect(layout.zoneAt(4), ReceiptLineZone.footer);
  });

  test('classifies metadata table line as header not body', () {
    const ocr =
        'MY KOPITIAM\n'
        'Table: 5\n'
        'Nasi Lemak          RM 8.00\n'
        'Teh O               RM 2.50\n'
        'Subtotal            RM 10.50\n'
        'TOTAL               RM 10.50';
    final texts = ocr.split('\n');
    final layout = analyzeReceiptLayout(ocr, _linesWithTexts(texts));
    expect(layout, isNotNull);
    expect(layout!.zoneAt(1), ReceiptLineZone.header);
    expect(layout.zoneAt(2), ReceiptLineZone.body);
  });

  test('returns null when no item or footer structure is detectable', () {
    const ocr = 'LINE ONE\nLINE TWO\nLINE THREE\nLINE FOUR';
    final layout = analyzeReceiptLayout(ocr, _linesForText(ocr));
    expect(layout, isNull);
  });

  test('zone indices match ReceiptLineItem.lineIndex raw-split convention', () {
    const ocr =
        'RESTORAN MAJU\n'
        'Nasi Lemak          RM 8.00\n'
        'Teh O               RM 2.50\n'
        'TOTAL               RM 10.50';
    final texts = ocr.split('\n');
    final layout = analyzeReceiptLayout(ocr, _linesWithTexts(texts));
    expect(layout, isNotNull);
    final items = extractReceiptLineItems(ocr).items;
    expect(items, isNotEmpty);
    for (final item in items) {
      final idx = item.lineIndex;
      expect(idx, isNotNull);
      expect(layout!.zoneAt(idx!), ReceiptLineZone.body);
    }
  });
}
