import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/models/transaction_view.dart';
import 'demo_transactions.dart';
import 'ingest_receipt_request.dart';

/// In-memory transactions for Flutter Web (Drift/SQLite uses dart:ffi on native only).
class TransactionRepository {
  TransactionRepository();

  final _rows = <TransactionView>[];
  final _controller = StreamController<List<TransactionView>>.broadcast();
  static const _uuid = Uuid();

  Stream<List<TransactionView>> watchAll() {
    Future.microtask(_emit);
    return _controller.stream;
  }

  Future<TransactionView?> getById(String id) async {
    for (final row in _rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<TransactionView> ingestReceipt(IngestReceiptRequest request) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final view = TransactionView(
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
    );
    _rows.add(view);
    _emit();
    return view;
  }

  Future<void> updateTransaction(TransactionView view) async {
    final i = _rows.indexWhere((r) => r.id == view.id);
    if (i >= 0) {
      _rows[i] = view;
      _emit();
    }
  }

  Future<void> retryStuckSync() async {
    for (var i = 0; i < _rows.length; i++) {
      if (_rows[i].isStuckSync) {
        _rows[i] = TransactionView(
          id: _rows[i].id,
          occurredAt: _rows[i].occurredAt,
          amountMyr: _rows[i].amountMyr,
          needsAmount: _rows[i].needsAmount,
          merchantRaw: _rows[i].merchantRaw,
          categoryGuess: _rows[i].categoryGuess,
          categoryUser: _rows[i].categoryUser,
          placeName: _rows[i].placeName,
          placeGooglePlaceId: _rows[i].placeGooglePlaceId,
          placeLat: _rows[i].placeLat,
          placeLng: _rows[i].placeLng,
          syncStatus: 'pending',
          pipelineStatus: _rows[i].pipelineStatus,
          localThumbnailPath: _rows[i].localThumbnailPath,
          thumbnailBytes: _rows[i].thumbnailBytes,
          impactUser: _rows[i].impactUser,
        );
      }
    }
    _emit();
  }

  Future<void> deleteTransaction(String id) async {
    _rows.removeWhere((r) => r.id == id);
    _emit();
  }

  Future<void> clearAll() async {
    _rows.clear();
    _emit();
  }

  Future<int> countAll() async => _rows.length;

  Future<void> seedDemoDataIfEmpty({String userId = 'demo-user'}) async {
    if (_rows.isNotEmpty) return;
    _rows.addAll(demoTransactions(userId: userId));
    _emit();
  }

  void _emit() {
    final sorted = [..._rows]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (!_controller.isClosed) {
      _controller.add(sorted);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
