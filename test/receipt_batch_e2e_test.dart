import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/category_matcher_bundled.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';
import 'package:receipt_drop/features/share/receipt_batch_e2e.dart';
import 'package:receipt_drop/features/share/receipt_ingest_draft.dart';
import 'package:receipt_drop/features/share/receipt_parse_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CategoryConfig categories;

  setUpAll(() async {
    categories = await loadBundledCategoryConfig();
  });

  test('ReceiptIngestDraft.toIngestRequest carries line items through', () {
    const draft = ReceiptIngestDraft(
      localFilePath: '/tmp/receipt.png',
      mimeType: 'image/png',
      amountMyr: 20.4,
      needsAmount: false,
      merchantRaw: 'Rock Cafe',
      categoryGuess: 'Food & Drink',
      lineItems: [
        ReceiptLineItem(name: 'Latte', priceMyr: 12.5),
        ReceiptLineItem(name: 'Croissant', priceMyr: 7.9),
      ],
    );

    final request = draft.toIngestRequest(confirmedAmount: 20.4);
    expect(request.needsAmount, isFalse);
    expect(request.lineItems, hasLength(2));
    expect(request.lineItems.first.name, 'Latte');
  });

  test('persistParsedReceiptE2e round-trips line items through outbox', () async {
    const ocrText = '''
ROCK CAFE SDN BHD
Latte                      RM 12.50
Croissant                  RM 7.90
TOTAL                      RM 20.40
''';
    final parsed = parseReceiptOcrText(
      filePath: '/tmp/rock_cafe_items.png',
      ocrText: ocrText,
      categories: categories,
    );

    final e2e = await persistParsedReceiptE2e(
      parsed: parsed,
      mimeType: 'image/png',
    );

    expect(e2e.roundTripOk, isTrue);
    expect(e2e.persistedLineItemNames, ['Latte', 'Croissant']);
    expect(e2e.syncLineItemsPayload, hasLength(2));
    expect(e2e.syncLineItemsPayload.first['name'], 'Latte');
    expect(e2e.syncLineItemsPayload.first['price_myr'], 12.5);
    expect(e2e.syncLineItemsPayload.first['sort_order'], 0);
    expect(e2e.needsReview, isFalse);
    expect(e2e.pipelineStatus, 'provisional');
  });

  test('persistParsedReceiptE2e queues needs-amount receipts for review',
      () async {
    final parsed = parseReceiptOcrText(
      filePath: '/tmp/blank.png',
      ocrText: 'UNKNOWN SHOP\nNo totals here',
      categories: categories,
    );

    final e2e = await persistParsedReceiptE2e(
      parsed: parsed,
      mimeType: 'image/png',
    );

    // The receipt is persisted into the review queue, never dropped.
    expect(e2e.needsReview, isTrue);
    expect(e2e.pipelineStatus, 'needs_review');
    expect(e2e.transactionId, isNotEmpty);
  });

  test('draftFromParseResult keeps rawOcrText even for a clean, confident parse',
      () {
    // A confident parse (needsAmount=false, lowConfidence=false) used to
    // drop rawOcrText entirely. The server-side LLM receipt-understanding
    // step needs the full OCR body regardless of parse confidence, so it
    // must now be carried through unconditionally whenever OCR found text.
    const ocrText = '''
ROCK CAFE SDN BHD
123 JALAN EXAMPLE
Latte                      RM 12.50
Croissant                  RM 7.90
TOTAL                      RM 20.40
''';
    final parsed = parseReceiptOcrText(
      filePath: '/tmp/rock_cafe_clean.png',
      ocrText: ocrText,
      categories: categories,
    );

    expect(parsed.needsAmount, isFalse);
    expect(parsed.lowConfidence, isFalse);

    final draft = draftFromParseResult(parsed: parsed, mimeType: 'image/png');

    expect(draft.rawOcrText, isNotNull);
    expect(draft.rawOcrText, contains('ROCK CAFE'));
  });
}
