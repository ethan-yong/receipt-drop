import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/transaction_view.dart';
import 'demo_transactions.dart';
import 'ingest_receipt_request.dart';
import 'places_repository.dart';

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
      pipelineStatus: request.needsReview ? 'needs_review' : 'provisional',
      localThumbnailPath: request.localFilePath,
      thumbnailBytes: request.thumbnailBytes,
      impactUser: request.impactUser,
      lineItems: request.lineItems,
      rawOcrText: request.rawOcrText,
      ocrConfidence: request.ocrConfidence,
    );
    _rows.add(view);
    _emit();
    return view;
  }

  final _needsReviewController =
      StreamController<List<TransactionView>>.broadcast();

  Stream<List<TransactionView>> watchNeedsReview() {
    Future.microtask(_emitNeedsReview);
    return _needsReviewController.stream;
  }

  void _emitNeedsReview() {
    final queued = _rows.where((r) => r.needsReview).toList()
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (!_needsReviewController.isClosed) {
      _needsReviewController.add(queued);
    }
  }

  Future<void> confirmReview(
    String id,
    double amountMyr, {
    String? impactUser,
  }) async {
    final i = _rows.indexWhere((r) => r.id == id);
    if (i < 0) return;
    final row = _rows[i];
    _rows[i] = TransactionView(
      id: row.id,
      occurredAt: row.occurredAt,
      amountMyr: amountMyr,
      needsAmount: false,
      merchantRaw: row.merchantRaw,
      categoryGuess: row.categoryGuess,
      categoryUser: row.categoryUser,
      placeName: row.placeName,
      placeGooglePlaceId: row.placeGooglePlaceId,
      placeLat: row.placeLat,
      placeLng: row.placeLng,
      syncStatus: 'pending',
      pipelineStatus: 'provisional',
      localThumbnailPath: row.localThumbnailPath,
      thumbnailBytes: row.thumbnailBytes,
      impactUser: impactUser ?? row.impactUser,
      lineItems: row.lineItems,
      rawOcrText: row.rawOcrText,
      ocrConfidence: row.ocrConfidence,
    );
    _emit();
  }

  Future<void> updateTransaction(TransactionView view) async {
    final i = _rows.indexWhere((r) => r.id == view.id);
    if (i >= 0) {
      _rows[i] = view;
      _emit();
    }
  }

  Future<void> updateTransactionPlace(String id, PlaceResult place) async {
    final i = _rows.indexWhere((r) => r.id == id);
    if (i >= 0) {
      _rows[i] = _rows[i].copyWith(
        placeName: place.name,
        placeGooglePlaceId: place.id,
        placeLat: place.lat,
        placeLng: place.lng,
      );
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
          lineItems: _rows[i].lineItems,
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

  Future<void> seedReceiptShowcaseIfEmpty({String userId = 'demo-user'}) async {
    if (!kDebugMode) return;
    final today = todaysTransactions(_rows, DateTime.now());
    if (hasFullReceiptShowcase(today)) return;

    for (final view in receiptShowcaseTransactions(userId: userId)) {
      final i = _rows.indexWhere((r) => r.id == view.id);
      if (i >= 0) {
        _rows[i] = view;
      } else {
        _rows.add(view);
      }
    }
    _emit();
  }

  void _emit() {
    final sorted = [..._rows]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (!_controller.isClosed) {
      _controller.add(sorted);
    }
    _emitNeedsReview();
  }

  Future<void> dispose() async {
    await _needsReviewController.close();
    await _controller.close();
  }
}
