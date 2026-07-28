import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/local/app_database.dart';
import 'package:receipt_drop/data/repositories/ingest_receipt_request.dart';
import 'package:receipt_drop/data/repositories/places_repository.dart';
import 'package:receipt_drop/data/repositories/transaction_repository_native.dart';
import 'package:receipt_drop/domain/models/receipt_display_image.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';
import 'package:receipt_drop/domain/models/receipt_understanding.dart';

const _fixtureConfidence = ReceiptUnderstandingConfidence(
  merchant: 0,
  address: 0,
  category: 0,
  lineItems: 0,
);

void main() {
  test('fresh in-memory database creates the line items table', () async {
    final db = AppDatabase.memory();
    final rows = await db.select(db.outboxLineItems).get();
    expect(rows, isEmpty);
    await db.close();
  });

  test('ingestReceipt + watchAll round-trips line items in order', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    const items = [
      ReceiptLineItem(name: 'Latte', priceMyr: 12.5, quantity: 1, confidence: 0.9),
      ReceiptLineItem(name: 'Croissant', priceMyr: 7.9),
    ];

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/receipt.png',
        mimeType: 'image/png',
        amountMyr: 20.4,
        needsAmount: false,
        merchantRaw: 'Rock Cafe',
        categoryGuess: 'Food & Drink',
        lineItems: items,
      ),
    );

    expect(saved.lineItems, isNotNull);
    expect(saved.lineItems!.map((i) => i.name), ['Latte', 'Croissant']);

    final rows = await repo.watchAll().first;
    expect(rows, hasLength(1));
    final rowItems = rows.single.lineItems;
    expect(rowItems, isNotNull);
    expect(rowItems!.map((i) => i.name), ['Latte', 'Croissant']);
    expect(rowItems[0].priceMyr, 12.5);
    expect(rowItems[0].quantity, 1);
    expect(rowItems[0].confidence, 0.9);
    expect(rowItems[1].quantity, isNull);
    expect(rowItems[1].confidence, isNull);

    await db.close();
  });

  test('getById round-trips line items', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    const items = [
      ReceiptLineItem(name: 'Milo Can', priceMyr: 6.0, quantity: 2),
      ReceiptLineItem(name: 'Bread Loaf', priceMyr: 4.5),
    ];

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/receipt2.png',
        mimeType: 'image/png',
        amountMyr: 10.5,
        needsAmount: false,
        merchantRaw: 'Freshmart',
        categoryGuess: 'Groceries',
        lineItems: items,
      ),
    );

    final fetched = await repo.getById(saved.id);
    expect(fetched, isNotNull);
    expect(fetched!.lineItems!.map((i) => i.name), ['Milo Can', 'Bread Loaf']);

    await db.close();
  });

  test('deleting a transaction cascades to its line items', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/receipt3.png',
        mimeType: 'image/png',
        amountMyr: 5.0,
        needsAmount: false,
        merchantRaw: 'Shop',
        categoryGuess: 'Others',
        lineItems: [ReceiptLineItem(name: 'Widget', priceMyr: 5.0)],
      ),
    );

    await repo.deleteTransaction(saved.id);

    final remaining = await (db.select(db.outboxLineItems)
          ..where((li) => li.transactionId.equals(saved.id)))
        .get();
    expect(remaining, isEmpty);

    await db.close();
  });

  test('needs-review ingest persists evidence and routes to the queue',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/blurry.png',
        mimeType: 'image/png',
        amountMyr: null,
        needsAmount: true,
        merchantRaw: 'Mamak Bistro',
        categoryGuess: 'Food & Drink',
        needsReview: true,
        rawOcrText: 'MEE GORENG 7.00 -Z\nJUMLAH 18.00',
        ocrServiceConfidence: 0.42,
        lineItemsConfidence: 0.3,
        parseFailureReason: 'no_amount_pattern',
      ),
    );

    expect(saved.needsReview, isTrue);
    expect(saved.pipelineStatus, 'needs_review');

    final queued = await repo.watchNeedsReview().first;
    expect(queued, hasLength(1));
    expect(queued.single.id, saved.id);
    expect(queued.single.rawOcrText, contains('MEE GORENG'));

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.rawOcrText, contains('JUMLAH'));
    expect(row.ocrServiceConfidence, 0.42);
    expect(row.lineItemsConfidence, 0.3);
    expect(row.parseFailureReason, 'no_amount_pattern');
    expect(row.amountSource, isNull);

    await db.close();
  });

  test('persists the LLM OCR-cleanup fields as their own columns', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final understanding = ReceiptUnderstanding(
      merchantName: 'Kedai Ali',
      merchantSearchQueries: const ['Kedai Ali'],
      addressText: null,
      locationClues: const [],
      vendorCategory: null,
      googlePlaceTypes: const [],
      lineItems: const [],
      confidence: _fixtureConfidence,
      cleanedLines: const ['Kedai Ali', 'TOTAL RM7.70'],
      cleanedOcrText: 'Kedai Ali\nTOTAL RM7.70',
      corrections: const [
        ReceiptUnderstandingCorrection(
          lineIndex: 1,
          original: 'T0TAL RM7.70',
          corrected: 'TOTAL RM7.70',
        ),
      ],
    );

    final saved = await repo.ingestReceipt(
      IngestReceiptRequest(
        localFilePath: '/tmp/cleanup.png',
        mimeType: 'image/png',
        amountMyr: 7.70,
        needsAmount: false,
        merchantRaw: 'Kedai Ali',
        categoryGuess: 'Food & Drink',
        rawOcrText: 'Kedai Ali\nT0TAL RM7.70',
        understanding: understanding,
      ),
    );

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.cleanedOcrText, 'Kedai Ali\nTOTAL RM7.70');
    expect(
      row.ocrCorrectionsJson,
      contains('T0TAL RM7.70'),
    );
    // The raw OCR field is untouched by the cleanup fields above.
    expect(row.rawOcrText, 'Kedai Ali\nT0TAL RM7.70');

    await db.close();
  });

  test('leaves the cleanup columns null when no cleanup was attempted',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/no_cleanup.png',
        mimeType: 'image/png',
        amountMyr: 7.70,
        needsAmount: false,
        merchantRaw: 'Kedai Ali',
        categoryGuess: 'Food & Drink',
      ),
    );

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.cleanedOcrText, isNull);
    expect(row.ocrCorrectionsJson, isNull);

    await db.close();
  });

  test('confirmReview releases the row back into the normal pipeline',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/blurry2.png',
        mimeType: 'image/png',
        amountMyr: null,
        needsAmount: true,
        merchantRaw: 'Shop',
        categoryGuess: 'Others',
        needsReview: true,
      ),
    );

    await repo.confirmReview(saved.id, 18.00, impactUser: 'low');

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.amountMyr, 18.00);
    expect(row.needsAmount, isFalse);
    expect(row.amountSource, 'user');
    expect(row.pipelineStatus, 'provisional');
    expect(row.syncStatus, 'pending');
    expect(row.impactUser, 'low');

    final queued = await repo.watchNeedsReview().first;
    expect(queued, isEmpty);

    await db.close();
  });

  test('normal ingest does not land in the review queue', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/clean.png',
        mimeType: 'image/png',
        amountMyr: 12.5,
        needsAmount: false,
        merchantRaw: 'Cafe',
        categoryGuess: 'Food & Drink',
      ),
    );

    final queued = await repo.watchNeedsReview().first;
    expect(queued, isEmpty);

    await db.close();
  });

  test('ingestReceipt with no line items round-trips to an empty list', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/receipt4.png',
        mimeType: 'image/png',
        amountMyr: 3.0,
        needsAmount: false,
        merchantRaw: 'Shop',
        categoryGuess: 'Others',
      ),
    );

    expect(saved.lineItems, isEmpty);

    final rows = await repo.watchAll().first;
    expect(rows.single.lineItems, isEmpty);

    await db.close();
  });

  test('ingestReceipt with guess place writes guess status without requiring lock',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/guess.png',
        mimeType: 'image/png',
        amountMyr: 18.0,
        needsAmount: false,
        merchantRaw: 'Starbucks 1 Utama',
        categoryGuess: 'Food & Drink',
        pickedPlaceName: 'Starbucks 1 Utama',
        pickedPlaceGooglePlaceId: 'ChIJ_guess',
        pickedPlaceLat: 3.15,
        pickedPlaceLng: 101.62,
        pickedPlaceLocked: false,
        shareLocationLat: 3.0,
        shareLocationLng: 101.5,
      ),
    );

    expect(saved.placeGooglePlaceId, 'ChIJ_guess');
    expect(saved.placeLat, closeTo(3.15, 0.0001));
    expect(saved.placeLng, closeTo(101.62, 0.0001));
    expect(saved.placeLat, isNot(closeTo(3.0, 0.0001)));

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.placeStatus, 'guess');

    await db.close();
  });

  test('ingestReceipt with pickedPlaceLocked writes user_locked status and place fields',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/picked.png',
        mimeType: 'image/png',
        amountMyr: 22.0,
        needsAmount: false,
        merchantRaw: 'Cafe Somewhere',
        categoryGuess: 'Food & Drink',
        pickedPlaceName: 'My Chosen Cafe',
        pickedPlaceGooglePlaceId: 'ChIJ_test_picked',
        pickedPlaceLat: 3.5,
        pickedPlaceLng: 101.5,
        pickedPlaceLocked: true,
      ),
    );

    expect(saved.placeGooglePlaceId, 'ChIJ_test_picked');
    expect(saved.placeName, 'My Chosen Cafe');
    expect(saved.placeLat, closeTo(3.5, 0.0001));
    expect(saved.placeLng, closeTo(101.5, 0.0001));

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.placeStatus, 'user_locked');
    expect(row.placeGooglePlaceId, 'ChIJ_test_picked');
    expect(row.placeName, 'My Chosen Cafe');

    await db.close();
  });

  test('updateTransactionPlace writes user_locked status and all place fields',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/to_update.png',
        mimeType: 'image/png',
        amountMyr: 15.0,
        needsAmount: false,
        merchantRaw: 'Unknown Shop',
        categoryGuess: 'Others',
      ),
    );

    const place = PlaceResult(
      id: 'ChIJabc_real',
      name: 'Real Cafe Name',
      address: '99 Jalan Real, KL',
      lat: 3.1234,
      lng: 101.6789,
    );

    await repo.updateTransactionPlace(saved.id, place);

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();

    expect(row.placeGooglePlaceId, 'ChIJabc_real');
    expect(row.placeName, 'Real Cafe Name');
    expect(row.placeLat, closeTo(3.1234, 0.0001));
    expect(row.placeLng, closeTo(101.6789, 0.0001));
    expect(row.placeStatus, 'user_locked');
    expect(row.syncStatus, 'pending');
    expect(row.retryCount, 0);

    await db.close();
  });

  test(
      'updateTransaction re-queues sync instead of silently leaving edits '
      'unsynced', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/edit_me.png',
        mimeType: 'image/png',
        amountMyr: 15.0,
        needsAmount: false,
        merchantRaw: 'Edit Cafe',
        categoryGuess: 'Food & Drink',
      ),
    );

    // Simulate a receipt that already finished its initial sync, so this
    // test actually exercises "an edit re-queues sync" rather than
    // coincidentally passing because ingestReceipt already leaves new rows
    // pending.
    await (db.update(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .write(const OutboxTransactionsCompanion(syncStatus: Value('synced')));

    final beforeEdit = await repo.getById(saved.id);
    final updated = beforeEdit!.copyWith(amountMyr: 30.0, categoryUser: 'Groceries');
    await repo.updateTransaction(updated);

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();

    expect(row.amountMyr, 30.0);
    expect(row.categoryUser, 'Groceries');
    expect(row.syncStatus, 'pending');
    expect(row.retryCount, 0);

    await db.close();
  });

  test('resolveDisplayImage returns local when file exists', () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final temp = await File(
      '${Directory.systemTemp.path}/rd_display_${DateTime.now().microsecondsSinceEpoch}.jpg',
    ).create();
    await temp.writeAsBytes([0xFF, 0xD8, 0xFF]);

    final saved = await repo.ingestReceipt(
      IngestReceiptRequest(
        localFilePath: temp.path,
        mimeType: 'image/jpeg',
        amountMyr: 10,
        needsAmount: false,
        merchantRaw: 'Cafe',
        categoryGuess: 'Food & Drink',
      ),
    );

    final image = await repo.resolveDisplayImage(saved.id);
    expect(image.source, ReceiptDisplayImageSource.local);
    expect(image.localPath, temp.path);

    await temp.delete();
    await db.close();
  });

  test('resolveDisplayImage is unavailable when local gone and no storage',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/does_not_exist_rd.jpg',
        mimeType: 'image/jpeg',
        amountMyr: 10,
        needsAmount: false,
        merchantRaw: 'Cafe',
        categoryGuess: 'Food & Drink',
      ),
    );

    final image = await repo.resolveDisplayImage(saved.id);
    expect(image.source, ReceiptDisplayImageSource.unavailable);
    expect(image.isAvailable, isFalse);

    await db.close();
  });

  test('replaceArtifactAndReprocess keeps one artifact and OCR fields',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    final saved = await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/old_receipt.png',
        mimeType: 'image/png',
        amountMyr: 12.0,
        needsAmount: false,
        merchantRaw: 'Old Merchant',
        categoryGuess: 'Others',
        categoryUser: 'Groceries',
        impactUser: 'low',
        lineItems: [
          ReceiptLineItem(name: 'Old Item', priceMyr: 12.0),
        ],
      ),
    );

    // Simulate a user-locked place that must survive retake.
    await repo.updateTransactionPlace(
      saved.id,
      const PlaceResult(
        id: 'place_locked',
        name: 'Locked Cafe',
        address: '1 Jalan Locked',
        lat: 3.1,
        lng: 101.6,
      ),
    );

    final oldArtifacts = await (db.select(db.outboxArtifacts)
          ..where((a) => a.transactionId.equals(saved.id)))
        .get();
    expect(oldArtifacts, hasLength(1));
    final oldArtifactId = oldArtifacts.single.id;

    final updated = await repo.replaceArtifactAndReprocess(
      saved.id,
      const IngestReceiptRequest(
        localFilePath: '/tmp/new_receipt.png',
        mimeType: 'image/png',
        amountMyr: 25.5,
        needsAmount: false,
        merchantRaw: 'New Merchant',
        categoryGuess: 'Food & Drink',
        ocrConfidence: 0.9,
        lineItems: [
          ReceiptLineItem(name: 'New Item', priceMyr: 25.5),
        ],
      ),
    );

    final artifacts = await (db.select(db.outboxArtifacts)
          ..where((a) => a.transactionId.equals(saved.id)))
        .get();
    expect(artifacts, hasLength(1));
    expect(artifacts.single.id, isNot(oldArtifactId));
    expect(artifacts.single.localFilePath, '/tmp/new_receipt.png');
    expect(artifacts.single.storagePath, isNull);

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(saved.id)))
        .getSingle();
    expect(row.merchantRaw, 'New Merchant');
    expect(row.amountMyr, 25.5);
    expect(row.categoryGuess, 'Food & Drink');
    expect(row.categoryUser, 'Groceries'); // user-owned preserved
    expect(row.impactUser, 'low'); // user-owned preserved
    expect(row.placeStatus, 'user_locked');
    expect(row.placeName, 'Locked Cafe');
    expect(row.syncStatus, 'pending');
    expect(row.retryCount, 0);
    expect(row.pipelineStatus, 'provisional');

    expect(updated.localThumbnailPath, '/tmp/new_receipt.png');
    expect(updated.lineItems!.map((i) => i.name), ['New Item']);

    final lineItems = await (db.select(db.outboxLineItems)
          ..where((li) => li.transactionId.equals(saved.id)))
        .get();
    expect(lineItems, hasLength(1));
    expect(lineItems.single.name, 'New Item');

    await db.close();
  });

  test(
      'hydrateFromCloudIfEmpty is a no-op when this user already has local rows',
      () async {
    final db = AppDatabase.memory();
    final repo = TransactionRepository(db);

    await repo.ingestReceipt(
      const IngestReceiptRequest(
        localFilePath: '/tmp/receipt.png',
        mimeType: 'image/png',
        amountMyr: 10,
        needsAmount: false,
        merchantRaw: 'Existing Cafe',
        categoryGuess: 'Food & Drink',
        userId: 'user-1',
      ),
    );

    // No Supabase config in the test environment either way, but the
    // existing-local-rows guard must short-circuit before any network call
    // is attempted, and must never duplicate or wipe what's already there.
    await repo.hydrateFromCloudIfEmpty('user-1');

    final rows = await repo.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.merchantRaw, 'Existing Cafe');

    await db.close();
  });
}
