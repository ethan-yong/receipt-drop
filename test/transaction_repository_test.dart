import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/local/app_database.dart';
import 'package:receipt_drop/data/repositories/ingest_receipt_request.dart';
import 'package:receipt_drop/data/repositories/transaction_repository_native.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';

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
}
