import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/transaction_view.dart';
import '../local/app_database.dart';
import 'demo_transactions.dart';
import 'ingest_receipt_request.dart';
import 'sync_worker.dart';

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<TransactionView>> watchAll() {
    return (_db.select(_db.outboxTransactions)
          ..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
          ]))
        .watch()
        .asyncMap(_rowsToViews);
  }

  Future<List<TransactionView>> _rowsToViews(
    List<OutboxTransaction> rows,
  ) async {
    final views = <TransactionView>[];
    for (final row in rows) {
      final path = await _artifactPathFor(row.id);
      final items = await _lineItemsFor(row.id);
      views.add(_mapRow(row, path, items));
    }
    return views;
  }

  Future<TransactionView?> getById(String id) async {
    final row = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final path = await _artifactPathFor(id);
    final items = await _lineItemsFor(id);
    return _mapRow(row, path, items);
  }

  Stream<List<TransactionView>> watchUnritualled() {
    return (_db.select(_db.outboxTransactions)
          ..where((t) => t.ritualledAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.occurredAt),
          ]))
        .watch()
        .asyncMap(_rowsToViews);
  }

  Future<void> markAsRitualled(List<String> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now();
    for (final id in ids) {
      await (_db.update(_db.outboxTransactions)..where((t) => t.id.equals(id)))
          .write(OutboxTransactionsCompanion(ritualledAt: Value(now)));
    }
  }

  Future<TransactionView> ingestReceipt(IngestReceiptRequest request) async {
    final id = _uuid.v4();
    final artifactId = _uuid.v4();
    final now = DateTime.now();
    final amountSource = request.needsAmount ? null : 'ocr';

    await _db.into(_db.outboxTransactions).insert(
          OutboxTransactionsCompanion.insert(
            id: id,
            userId: request.userId,
            occurredAt: Value(now),
            amountMyr: Value(request.amountMyr),
            amountSource: Value(amountSource),
            needsAmount: Value(request.needsAmount),
            merchantRaw: Value(request.merchantRaw),
            categoryGuess: Value(request.categoryGuess),
            shareLocationLat: Value(request.shareLocationLat),
            shareLocationLng: Value(request.shareLocationLng),
            shareLocationCapturedAt: Value(request.shareLocationCapturedAt),
            ocrConfidence: Value(request.ocrConfidence),
            impactUser: Value(request.impactUser),
            syncStatus: const Value('pending'),
            pipelineStatus: const Value('provisional'),
          ),
        );

    await _db.into(_db.outboxArtifacts).insert(
          OutboxArtifactsCompanion.insert(
            id: artifactId,
            userId: request.userId,
            transactionId: id,
            mimeType: request.mimeType,
            localFilePath: request.localFilePath,
          ),
        );

    if (request.lineItems.isNotEmpty) {
      await _db.batch((batch) {
        batch.insertAll(_db.outboxLineItems, [
          for (var i = 0; i < request.lineItems.length; i++)
            OutboxLineItemsCompanion.insert(
              id: _uuid.v4(),
              userId: request.userId,
              transactionId: id,
              name: request.lineItems[i].name,
              priceMyr: request.lineItems[i].priceMyr,
              quantity: Value(request.lineItems[i].quantity),
              confidence: Value(request.lineItems[i].confidence),
              sortOrder: i,
            ),
        ]);
      });
    }

    unawaited(SyncWorker.run(_db, id));

    return TransactionView(
      id: id,
      occurredAt: now,
      amountMyr: request.amountMyr,
      needsAmount: request.needsAmount,
      merchantRaw: request.merchantRaw,
      categoryGuess: request.categoryGuess,
      categoryUser: null,
      placeName: null,
      placeGooglePlaceId: null,
      placeLat: request.shareLocationLat,
      placeLng: request.shareLocationLng,
      syncStatus: 'pending',
      pipelineStatus: 'provisional',
      localThumbnailPath: request.localFilePath,
      thumbnailBytes: request.thumbnailBytes,
      impactUser: request.impactUser,
      ritualledAt: null,
      lineItems: request.lineItems,
    );
  }

  Future<void> updateTransaction(TransactionView view) async {
    await (_db.update(_db.outboxTransactions)
          ..where((t) => t.id.equals(view.id)))
        .write(
      OutboxTransactionsCompanion(
        amountMyr: Value(view.amountMyr),
        needsAmount: Value(view.needsAmount),
        categoryUser: Value(view.categoryUser),
        placeName: Value(view.placeName),
        placeGooglePlaceId: Value(view.placeGooglePlaceId),
        placeLat: Value(view.placeLat),
        placeLng: Value(view.placeLng),
        occurredAt: Value(view.occurredAt),
        impactUser: Value(view.impactUser),
      ),
    );
  }

  Future<void> retryStuckSync() async {
    final stuck = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.syncStatus.equals('stuck')))
        .get();
    for (final row in stuck) {
      await (_db.update(_db.outboxTransactions)..where((t) => t.id.equals(row.id)))
          .write(
        const OutboxTransactionsCompanion(
          syncStatus: Value('pending'),
          retryCount: Value(0),
        ),
      );
    }

    final pending = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.syncStatus.equals('pending')))
        .get();
    for (final row in pending) {
      unawaited(SyncWorker.run(_db, row.id));
    }
  }

  Future<void> deleteTransaction(String id) async {
    await (_db.delete(_db.outboxTransactions)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> clearAll() async {
    await _db.delete(_db.outboxTransactions).go();
  }

  Future<void> dispose() async {}

  Future<int> countAll() async {
    final rows = await _db.select(_db.outboxTransactions).get();
    return rows.length;
  }

  Future<void> seedDemoDataIfEmpty({String userId = 'demo-user'}) async {
    final count = await countAll();
    if (count > 0) return;

    for (final view in demoTransactions(userId: userId)) {
      await _db.into(_db.outboxTransactions).insert(
            OutboxTransactionsCompanion.insert(
              id: view.id,
              userId: userId,
              occurredAt: Value(view.occurredAt),
              amountMyr: Value(view.amountMyr),
              needsAmount: Value(view.needsAmount),
              merchantRaw: Value(view.merchantRaw),
              categoryGuess: Value(view.categoryGuess),
              placeName: Value(view.placeName),
              placeLat: Value(view.placeLat),
              placeLng: Value(view.placeLng),
              syncStatus: Value(view.syncStatus),
              pipelineStatus: Value(view.pipelineStatus),
            ),
          );
    }
  }

  Future<void> seedReceiptShowcaseIfEmpty({String userId = 'demo-user'}) async {
    if (!kDebugMode) return;

    final rows = await _db.select(_db.outboxTransactions).get();
    final views = await _rowsToViews(rows);
    final today = todaysTransactions(views, DateTime.now());
    if (hasFullReceiptShowcase(today)) return;

    for (final view in receiptShowcaseTransactions(userId: userId)) {
      await _db.into(_db.outboxTransactions).insert(
            OutboxTransactionsCompanion.insert(
              id: view.id,
              userId: userId,
              occurredAt: Value(view.occurredAt),
              amountMyr: Value(view.amountMyr),
              needsAmount: Value(view.needsAmount),
              merchantRaw: Value(view.merchantRaw),
              categoryGuess: Value(view.categoryGuess),
              placeName: Value(view.placeName),
              placeLat: Value(view.placeLat),
              placeLng: Value(view.placeLng),
              syncStatus: Value(view.syncStatus),
              pipelineStatus: Value(view.pipelineStatus),
            ),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  Future<String?> _artifactPathFor(String transactionId) async {
    final artifact = await (_db.select(_db.outboxArtifacts)
          ..where((a) => a.transactionId.equals(transactionId)))
        .getSingleOrNull();
    return artifact?.localFilePath;
  }

  Future<List<ReceiptLineItem>> _lineItemsFor(String transactionId) async {
    final rows = await (_db.select(_db.outboxLineItems)
          ..where((li) => li.transactionId.equals(transactionId))
          ..orderBy([(li) => OrderingTerm.asc(li.sortOrder)]))
        .get();
    return rows
        .map((r) => ReceiptLineItem(
              name: r.name,
              priceMyr: r.priceMyr,
              quantity: r.quantity,
              confidence: r.confidence,
            ))
        .toList();
  }

  TransactionView _mapRow(
    OutboxTransaction row,
    String? localPath,
    List<ReceiptLineItem> lineItems,
  ) {
    return TransactionView(
      id: row.id,
      occurredAt: row.occurredAt,
      amountMyr: row.amountMyr,
      needsAmount: row.needsAmount,
      merchantRaw: row.merchantRaw,
      categoryGuess: row.categoryGuess,
      categoryUser: row.categoryUser,
      placeName: row.placeName,
      placeGooglePlaceId: row.placeGooglePlaceId,
      placeLat: row.placeLat,
      placeLng: row.placeLng,
      syncStatus: row.syncStatus,
      pipelineStatus: row.pipelineStatus,
      localThumbnailPath: localPath,
      impactUser: row.impactUser,
      ritualledAt: row.ritualledAt,
      lineItems: lineItems,
    );
  }
}
