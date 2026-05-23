import 'package:drift/drift.dart';

import '../../domain/models/transaction_view.dart';
import '../local/app_database.dart';
import 'demo_transactions.dart';

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  Stream<List<TransactionView>> watchAll() {
    return (_db.select(_db.outboxTransactions)
          ..orderBy([
            (t) => OrderingTerm.desc(t.occurredAt),
          ]))
        .watch()
        .map((rows) => rows.map(_mapRow).toList());
  }

  Future<TransactionView?> getById(String id) async {
    final row = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return null;
    return _mapRow(row);
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

  TransactionView _mapRow(OutboxTransaction row) {
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
      localThumbnailPath: null,
    );
  }
}
