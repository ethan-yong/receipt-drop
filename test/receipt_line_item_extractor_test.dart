import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/receipt_line_item_extractor.dart';
import 'package:receipt_drop/domain/models/receipt_line_zone.dart';

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

  test('parses a bare comma-decimal price with no tax suffix', () {
    const ocr = '''
KEDAI RUNCIT
Roti Canai                 3,00
''';
    final result = extractReceiptLineItems(ocr);
    expect(result.items.single.name, 'Roti Canai');
    expect(result.items.single.priceMyr, 3.00);
  });

  test('recovers all items from a noisy handheld-photo scan (real regression fixture)', () {
    // Actual Tesseract output for a real mamak receipt photographed in-hand
    // against a busy background (chairs/floor/people) — most lines pick up
    // stray characters from the scene, some prices come back comma-decimal
    // ("3,00" instead of "3.00"), and the -Z SST suffix sometimes misreads as
    // "-2"/"-7"/"~Z". This fixture pins the recovery of all 9 items despite
    // that noise.
    const ocr = '''
- : a a ~~ . ;
oo a
�t i
Ul }
lA
aimee
RESTORAN AME
REG.NO,t.cssoe
NO.1-A NADAYU28,JLN PJS 11/7
BANDAR SUNWAY 47500 SELANGOR.
TEL:
INVOICE
j ### MOBILE PAY x#4 :
nn a ne
; TAXNO. 3346131
4 TABLENO :62
eo. 4 TRAN NO :390705
& \\ DATE :10/Jun/2028 01:17:26
t \\ 1 Rsb Biasa 7.00 -Z ~.
~ VY Vy 3 Teh O Limau Ais 8.70 -2 A
eq Maggi G Double 11.00 -2 .
ae Limau Ais Bungkus 3,00 -2
� 1 Milo Ais Bungkus 4.20 ~Z \\
�ny Maggi Goreng Telur M 9,00 -2
yo Nasi G Ayam Mamak 12,50 -7 "n
1 Ayam Goreng 6.00 -Z �.
1 Teh Ais Bungkus 3.40 -2
"FE TOTAL : RM 64.80
CASH : RM 64.80 "
/ CHANGE : RM 0,00
{2 STAFF :MASTER
( THANK YOU COME AGAIN
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 64.80);
    expect(result.items.length, 9);
    expect(
      result.items.map((it) => it.priceMyr).toList(),
      [7.00, 8.70, 11.00, 3.00, 4.20, 9.00, 12.50, 6.00, 3.40],
    );
    // Mamak layout: qty printed before the name with no "x" ("1 Rsb Biasa
    // 7.00 -Z"). Lines whose qty digit was lost to scene noise fall through
    // to the bare pattern with a null quantity.
    expect(
      result.items.map((it) => it.quantity).toList(),
      [1, 3, null, null, 1, null, null, 1, 1],
    );
    // Leading/trailing punctuation junk is trimmed from names; alphabetic
    // junk ("eq", "yo") is indistinguishable from real words and remains.
    expect(
      result.items.map((it) => it.name).toList(),
      [
        'Rsb Biasa',
        'Teh O Limau Ais',
        'eq Maggi G Double',
        'ae Limau Ais Bungkus',
        'Milo Ais Bungkus',
        'ny Maggi Goreng Telur M',
        'yo Nasi G Ayam Mamak',
        'Ayam Goreng',
        'Teh Ais Bungkus',
      ],
    );
    expect(result.itemsSubtotalMyr, 64.80);
    expect(result.itemsMatchTotal, isTrue);
  });

  test('parses quantity-prefixed items without an "x" separator', () {
    const ocr = '''
RESTORAN ANWAR MAJU
1 Rsb Biasa 7.00 -Z
3 Teh O Limau Ais 8.70 -Z
1 Nasi Lemak RM 5.00
JUMLAH 20.70
''';
    final result = extractReceiptLineItems(ocr, totalMyr: 20.70);
    expect(result.items.length, 3);
    expect(result.items[0].quantity, 1);
    expect(result.items[0].name, 'Rsb Biasa');
    expect(result.items[1].quantity, 3);
    expect(result.items[1].name, 'Teh O Limau Ais');
    expect(result.items[2].quantity, 1);
    expect(result.items[2].name, 'Nasi Lemak');
    expect(result.items[2].priceMyr, 5.00);
    expect(result.itemsMatchTotal, isTrue);
  });

  test('does not read the tail of a longer number as a quantity', () {
    const ocr = '''
KEDAI RUNCIT
100 Plus 3.50
''';
    final result = extractReceiptLineItems(ocr);
    expect(result.items.single.quantity, isNull);
    expect(result.items.single.name, '100 Plus');
    expect(result.items.single.priceMyr, 3.50);
  });

  test('mid-line digits before "RM" stay part of the name, not a quantity', () {
    const ocr = '''
CAFE
Kopi 2 RM 6.00
''';
    final result = extractReceiptLineItems(ocr);
    expect(result.items.single.quantity, isNull);
    expect(result.items.single.name, 'Kopi 2');
    expect(result.items.single.priceMyr, 6.00);
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

  test('omitting layout or unreliable layout matches baseline extraction', () {
    const ocr = '''
ROCK CAFE SDN BHD
Latte                     RM 12.50
Croissant                 RM 7.90
TOTAL                     RM 20.40
''';
    final baseline = extractReceiptLineItems(ocr, totalMyr: 20.40);
    final withNull = extractReceiptLineItems(ocr, totalMyr: 20.40, layout: null);
    final withUnreliable = extractReceiptLineItems(
      ocr,
      totalMyr: 20.40,
      layout: const ReceiptLayoutAnalysis(
        zones: [
          ReceiptLineZone.header,
          ReceiptLineZone.body,
          ReceiptLineZone.body,
          ReceiptLineZone.footer,
        ],
        isReliable: false,
      ),
    );
    expect(withNull.items.map((i) => i.name).toList(),
        baseline.items.map((i) => i.name).toList());
    expect(withNull.items.map((i) => i.priceMyr).toList(),
        baseline.items.map((i) => i.priceMyr).toList());
    expect(withUnreliable.items.map((i) => i.name).toList(),
        baseline.items.map((i) => i.name).toList());
  });
}
