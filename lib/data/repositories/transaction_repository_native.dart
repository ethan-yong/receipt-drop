import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/transaction_view.dart';
import '../local/app_database.dart';
import 'demo_transactions.dart';
import 'ingest_receipt_request.dart';

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
      views.add(_mapRow(row, path));
    }
    return views;
  }

  Future<TransactionView?> getById(String id) async {
    final row = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    final path = await _artifactPathFor(id);
    return _mapRow(row, path);
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
      ),
    );
  }

  Future<void> retryStuckSync() async {
    await (_db.update(_db.outboxTransactions)
          ..where((t) => t.syncStatus.equals('stuck')))
        .write(
      const OutboxTransactionsCompanion(
        syncStatus: Value('pending'),
      ),
    );
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

  Future<String?> _artifactPathFor(String transactionId) async {
    final artifact = await (_db.select(_db.outboxArtifacts)
          ..where((a) => a.transactionId.equals(transactionId)))
        .getSingleOrNull();
    return artifact?.localFilePath;
  }

  TransactionView _mapRow(OutboxTransaction row, String? localPath) {
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
    );
  }
}
