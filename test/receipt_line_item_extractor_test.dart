import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/receipt_line_item_extractor.dart';

void main() {
  test('extracts >=2 items from a typical cafe receipt', () {
    const ocr = '''
ROCK CAFE SDN BHD
123 JALAN EXAMPLE

Latte                     RM 12.50
Croissant                 RM 7.90

SUBTOTAL                  RM 20.40
TOTAL                     RM 20.40
Thank you
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 20.40);
    expect(result.items.length, greaterThanOrEqualTo(2));
    expect(result.items[0].name, 'Latte');
    expect(result.items[0].priceMyr, 12.50);
    expect(result.items[1].name, 'Croissant');
    expect(result.items[1].priceMyr, 7.90);
    expect(result.itemsSubtotalMyr, 20.40);
    expect(result.itemsMatchTotal, isTrue);
  });

  test('extracts grocery multi-line items with quantity prefix', () {
    const ocr = '''
FRESHMART SDN BHD
No. 12, Jalan Enterprise

2 x Milo Can               RM 6.00
1 x Bread Loaf              RM 4.50
Broccoli                    RM 4.20

SUBTOTAL                    RM 14.70
ROUNDING                     RM 0.00
TOTAL                        RM 14.70
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 14.70);
    expect(result.items.length, 3);
    expect(result.items[0].quantity, 2);
    expect(result.items[0].name, 'Milo Can');
    expect(result.items[2].quantity, isNull);
    expect(result.itemsMatchTotal, isTrue);
  });

  test('excludes total/subtotal/tax/change lines', () {
    const ocr = '''
7-ELEVEN SUNWAY
Kopi O                     RM 3.50
Subtotal                   RM 3.50
TUNAI                      RM 5.00
Baki                       RM 1.50
TOTAL                      RM 3.50
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 3.50);
    expect(result.items.length, 1);
    expect(result.items.single.name, 'Kopi O');
  });

  test('returns empty result for empty OCR text', () {
    final result = extractReceiptLineItems('');
    expect(result.items, isEmpty);
    expect(result.confidence, 0.0);
    expect(result.itemsSubtotalMyr, isNull);
    expect(result.itemsMatchTotal, isFalse);
  });

  test('flags itemsMatchTotal false when subtotal is far from total', () {
    const ocr = '''
MYSTERY SHOP
Widget                     RM 5.00
TOTAL                      RM 50.00
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 50.00);
    expect(result.itemsSubtotalMyr, 5.00);
    expect(result.itemsMatchTotal, isFalse);
  });

  test('tolerates Malaysian SST tax-code suffixes after the price', () {
    const ocr = '''
RESTORAN PELITA
Teh Tarik                  2.50 SR
Roti Canai                 RM 1.50-Z
2 x Nasi Lemak             RM 9.00 ZRL
JUMLAH                     13.00
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 13.00);
    expect(result.items.length, 3);
    expect(result.items[0].name, 'Teh Tarik');
    expect(result.items[0].priceMyr, 2.50);
    expect(result.items[1].name, 'Roti Canai');
    expect(result.items[1].priceMyr, 1.50);
    expect(result.items[2].name, 'Nasi Lemak');
    expect(result.items[2].priceMyr, 9.00);
    expect(result.items[2].quantity, 2);
    expect(result.itemsSubtotalMyr, 13.00);
    expect(result.itemsMatchTotal, isTrue);
  });

  test('mamak fixture with bare -Z prices extracts all items', () {
    const ocr = '''
RESTORAN MAMAK BISTRO
Mee Goreng                 7.00 -Z
Nasi Kandar                11.00 -Z
''';
    final result = extractReceiptLineItems(ocr);
    expect(result.items.length, 2);
    expect(result.items[0].priceMyr, 7.00);
    expect(result.items[1].priceMyr, 11.00);
    expect(result.itemsSubtotalMyr, 18.00);
  });

  test('reconcileWithTotal applies match flag and penalty after the fact', () {
    const ocr = '''
CAFE
Latte                      RM 12.50
Croissant                  RM 7.90
''';
    final extracted = extractReceiptLineItems(ocr);
    expect(extracted.itemsMatchTotal, isFalse);

    final matched = reconcileWithTotal(extracted, 20.40);
    expect(matched.itemsMatchTotal, isTrue);
    expect(matched.confidence, extracted.confidence);

    final mismatched = reconcileWithTotal(extracted, 99.00);
    expect(mismatched.itemsMatchTotal, isFalse);
    expect(mismatched.confidence, lessThan(extracted.confidence));
  });
}
