import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/receipt_display_image.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/share/receipt_file_store.dart';
import '../local/app_database.dart';
import 'demo_transactions.dart';
import 'ingest_receipt_request.dart';
import 'places_repository.dart';
import 'sync_worker.dart';

/// Signed URL lifetime for private receipt photos. Short-lived and never
/// persisted — regenerated each time the detail/viewer screen opens.
const _signedUrlExpirySeconds = 60 * 60;

const bool _kDebugMode = !bool.fromEnvironment('dart.vm.product');

class TransactionRepository {
  TransactionRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<TransactionView>> watchAll() {
    return (_db.select(_db.outboxTransactions)..orderBy([
          (t) => OrderingTerm.desc(t.occurredAt),
          // Tie-break same-timestamp rows latest-captured-first, so a
          // fresh scan always leads the home carousel.
          (t) => OrderingTerm.desc(t.createdAt),
        ]))
        .watch()
        .asyncMap(_rowsToViews);
  }

  Future<List<TransactionView>> _rowsToViews(
    List<OutboxTransaction> rows,
  ) async {
    final views = <TransactionView>[];
    for (final row in rows) {
      final artifact = await _artifactFor(row.id);
      final items = await _lineItemsFor(row.id);
      views.add(_mapRow(row, artifact, items));
    }
    return views;
  }

  Future<TransactionView?> getById(String id) async {
    final row = await (_db.select(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final artifact = await _artifactFor(id);
    final items = await _lineItemsFor(id);
    return _mapRow(row, artifact, items);
  }

  /// Local file if it still exists; else a short-lived signed Storage URL;
  /// else unavailable (never synced / wiped before upload).
  Future<ReceiptDisplayImage> resolveDisplayImage(String transactionId) async {
    final artifact = await _artifactFor(transactionId);
    if (artifact == null) return const ReceiptDisplayImage.unavailable();

    final localPath = artifact.localFilePath;
    if (localPath.isNotEmpty && !localPath.startsWith('web:')) {
      try {
        if (await File(localPath).exists()) {
          return ReceiptDisplayImage.local(localPath);
        }
      } catch (_) {
        // Fall through to signed-URL / unavailable.
      }
    }

    final storagePath = artifact.storagePath;
    if (storagePath != null &&
        storagePath.isNotEmpty &&
        Env.hasSupabaseConfig) {
      try {
        final url = await Supabase.instance.client.storage
            .from('receipts')
            .createSignedUrl(storagePath, _signedUrlExpirySeconds);
        if (url.isNotEmpty) {
          return ReceiptDisplayImage.remote(url);
        }
      } catch (_) {
        // Fall through to unavailable.
      }
    }

    return const ReceiptDisplayImage.unavailable();
  }

  Future<TransactionView> ingestReceipt(IngestReceiptRequest request) async {
    final id = _uuid.v4();
    final artifactId = _uuid.v4();
    final now = DateTime.now();
    final amountSource = request.needsAmount ? null : 'ocr';
    final pipelineStatus = request.needsReview ? 'needs_review' : 'provisional';
    final encoded = _encodeOcrSideChannels(request);

    await _db
        .into(_db.outboxTransactions)
        .insert(
          OutboxTransactionsCompanion.insert(
            id: id,
            userId: request.userId,
            occurredAt: Value(now),
            amountMyr: Value(request.amountMyr),
            amountSource: Value(amountSource),
            needsAmount: Value(request.needsAmount),
            merchantRaw: Value(request.merchantRaw),
            categoryGuess: Value(request.categoryGuess),
            categoryConfidence: Value(request.categoryConfidence),
            categoryUser: Value(request.categoryUser),
            shareLocationLat: Value(request.shareLocationLat),
            shareLocationLng: Value(request.shareLocationLng),
            shareLocationCapturedAt: Value(request.shareLocationCapturedAt),
            ocrConfidence: Value(request.ocrConfidence),
            rawOcrText: Value(request.rawOcrText),
            ocrServiceConfidence: Value(request.ocrServiceConfidence),
            lineItemsConfidence: Value(request.lineItemsConfidence),
            parseFailureReason: Value(request.parseFailureReason),
            impactUser: Value(request.impactUser),
            syncStatus: const Value('pending'),
            pipelineStatus: Value(pipelineStatus),
            merchantCandidatesJson: Value(encoded.merchantCandidatesJson),
            ocrHeaderText: Value(request.ocrHeaderText),
            llmUnderstandingJson: Value(encoded.llmUnderstandingJson),
            // Own columns (not just nested inside llmUnderstandingJson above)
            // so cleanup output stays independently queryable — mirrors
            // rawOcrText's own-column precedent alongside the LLM blob.
            cleanedOcrText: Value(encoded.cleanedOcrText),
            ocrCorrectionsJson: Value(encoded.ocrCorrectionsJson),
            placeName: Value(
              request.pickedPlaceLocked ? request.pickedPlaceName : null,
            ),
            placeGooglePlaceId: Value(
              request.pickedPlaceLocked
                  ? request.pickedPlaceGooglePlaceId
                  : null,
            ),
            placeLat: Value(
              request.pickedPlaceLocked ? request.pickedPlaceLat : null,
            ),
            placeLng: Value(
              request.pickedPlaceLocked ? request.pickedPlaceLng : null,
            ),
            placeStatus: Value(
              request.pickedPlaceLocked ? 'user_locked' : 'none',
            ),
          ),
        );

    await _db
        .into(_db.outboxArtifacts)
        .insert(
          OutboxArtifactsCompanion.insert(
            id: artifactId,
            userId: request.userId,
            transactionId: id,
            mimeType: request.mimeType,
            localFilePath: request.localFilePath,
          ),
        );

    if (request.lineItems.isNotEmpty) {
      await _insertLineItems(id, request.userId, request.lineItems);
    }

    if (request.fieldCorrections.isNotEmpty) {
      await _db.batch((batch) {
        batch.insertAll(_db.outboxFieldCorrections, [
          for (final correction in request.fieldCorrections)
            OutboxFieldCorrectionsCompanion.insert(
              id: _uuid.v4(),
              userId: request.userId,
              transactionId: id,
              field: correction.field,
              predictedValue: correction.predictedValue,
              confirmedValue: correction.confirmedValue,
              merchantRaw: Value(correction.merchantRaw),
              confidence: Value(correction.confidence),
              correctionType: Value(correction.correctionType),
              lineItemIndex: Value(correction.lineItemIndex),
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
      placeName: request.pickedPlaceLocked ? request.pickedPlaceName : null,
      placeGooglePlaceId: request.pickedPlaceLocked
          ? request.pickedPlaceGooglePlaceId
          : null,
      placeLat: request.pickedPlaceLocked
          ? request.pickedPlaceLat
          : request.shareLocationLat,
      placeLng: request.pickedPlaceLocked
          ? request.pickedPlaceLng
          : request.shareLocationLng,
      syncStatus: 'pending',
      pipelineStatus: pipelineStatus,
      localThumbnailPath: request.localFilePath,
      remoteStoragePath: null,
      thumbnailBytes: request.thumbnailBytes,
      impactUser: request.impactUser,
      lineItems: request.lineItems,
      rawOcrText: request.rawOcrText,
      ocrConfidence: request.ocrConfidence,
      shareLocationLat: request.shareLocationLat,
      shareLocationLng: request.shareLocationLng,
    );
  }

  /// Replace the single artifact for [transactionId] and overwrite OCR-derived
  /// fields from a retake confirm. Preserves user-owned fields
  /// (`categoryUser` unless freshly set, `placeStatus`/`place*` unless newly
  /// locked, `impactUser` unless freshly set). Always leaves exactly one
  /// `outbox_artifacts` row so [SyncWorker.run]'s `getSingleOrNull()` stays
  /// valid.
  Future<TransactionView> replaceArtifactAndReprocess(
    String transactionId,
    IngestReceiptRequest request,
  ) async {
    final existing = await (_db.select(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
    if (existing == null) {
      throw StateError('Transaction $transactionId not found');
    }

    final oldArtifact = await _artifactFor(transactionId);
    final oldLocalPath = oldArtifact?.localFilePath;

    final newArtifactId = _uuid.v4();
    final pipelineStatus = request.needsReview ? 'needs_review' : 'provisional';

    await _db.transaction(() async {
      if (oldArtifact != null) {
        await (_db.delete(
          _db.outboxArtifacts,
        )..where((a) => a.id.equals(oldArtifact.id))).go();
      }

      await _db
          .into(_db.outboxArtifacts)
          .insert(
            OutboxArtifactsCompanion.insert(
              id: newArtifactId,
              userId: request.userId.isEmpty ? existing.userId : request.userId,
              transactionId: transactionId,
              mimeType: request.mimeType,
              localFilePath: request.localFilePath,
            ),
          );

      await (_db.delete(
        _db.outboxLineItems,
      )..where((li) => li.transactionId.equals(transactionId))).go();

      if (request.lineItems.isNotEmpty) {
        await _insertLineItems(
          transactionId,
          existing.userId,
          request.lineItems,
        );
      }

      await (_db.update(
        _db.outboxTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        _ocrDerivedUpdateCompanion(request, pipelineStatus: pipelineStatus),
      );
    });

    // Local file cleanup is best-effort and never blocks the replace.
    // Remote Storage / receipt_artifacts cleanup runs asynchronously in
    // SyncWorker after the new artifact uploads (single-version replace).
    if (oldLocalPath != null &&
        oldLocalPath.isNotEmpty &&
        oldLocalPath != request.localFilePath) {
      await deleteStoredReceipt(oldLocalPath);
    }

    unawaited(SyncWorker.run(_db, transactionId));

    final updated = await getById(transactionId);
    if (updated == null) {
      throw StateError('Transaction $transactionId missing after replace');
    }
    return updated;
  }

  /// Receipts parked in the review queue, newest first.
  Stream<List<TransactionView>> watchNeedsReview() {
    return (_db.select(_db.outboxTransactions)
          ..where((t) => t.pipelineStatus.equals('needs_review'))
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .watch()
        .asyncMap(_rowsToViews);
  }

  /// One-tap confirmation from the review screen: sets the user-entered
  /// amount, releases the row back into the normal pipeline, and re-queues
  /// sync (plain updates never re-sync on their own).
  Future<void> confirmReview(
    String id,
    double amountMyr, {
    String? impactUser,
  }) async {
    await (_db.update(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(id))).write(
      OutboxTransactionsCompanion(
        amountMyr: Value(amountMyr),
        needsAmount: const Value(false),
        amountSource: const Value('user'),
        pipelineStatus: const Value('provisional'),
        syncStatus: const Value('pending'),
        retryCount: const Value(0),
        impactUser: impactUser != null
            ? Value(impactUser)
            : const Value.absent(),
      ),
    );
    unawaited(SyncWorker.run(_db, id));
  }

  Future<void> updateTransaction(TransactionView view) async {
    await (_db.update(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(view.id))).write(
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

  Future<void> updateTransactionPlace(String id, PlaceResult place) async {
    await (_db.update(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(id))).write(
      OutboxTransactionsCompanion(
        placeName: Value(place.name),
        placeGooglePlaceId: Value(place.id),
        placeLat: Value(place.lat),
        placeLng: Value(place.lng),
        placeStatus: const Value('user_locked'),
        syncStatus: const Value('pending'),
        retryCount: const Value(0),
      ),
    );
    unawaited(SyncWorker.run(_db, id));
  }

  Future<void> retryStuckSync() async {
    final stuck = await (_db.select(
      _db.outboxTransactions,
    )..where((t) => t.syncStatus.equals('stuck'))).get();
    for (final row in stuck) {
      await (_db.update(
        _db.outboxTransactions,
      )..where((t) => t.id.equals(row.id))).write(
        const OutboxTransactionsCompanion(
          syncStatus: Value('pending'),
          retryCount: Value(0),
        ),
      );
    }

    final pending = await (_db.select(
      _db.outboxTransactions,
    )..where((t) => t.syncStatus.equals('pending'))).get();
    for (final row in pending) {
      unawaited(SyncWorker.run(_db, row.id));
    }
  }

  Future<void> deleteTransaction(String id) async {
    await (_db.delete(
      _db.outboxTransactions,
    )..where((t) => t.id.equals(id))).go();
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
      await _db
          .into(_db.outboxTransactions)
          .insert(
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
    if (!_kDebugMode) return;

    final rows = await _db.select(_db.outboxTransactions).get();
    final views = await _rowsToViews(rows);
    final today = todaysTransactions(views, DateTime.now());
    if (hasFullReceiptShowcase(today)) return;

    for (final view in receiptShowcaseTransactions(userId: userId)) {
      await _db
          .into(_db.outboxTransactions)
          .insert(
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

  Future<OutboxArtifact?> _artifactFor(String transactionId) async {
    return (_db.select(
      _db.outboxArtifacts,
    )..where((a) => a.transactionId.equals(transactionId))).getSingleOrNull();
  }

  Future<List<ReceiptLineItem>> _lineItemsFor(String transactionId) async {
    final rows =
        await (_db.select(_db.outboxLineItems)
              ..where((li) => li.transactionId.equals(transactionId))
              ..orderBy([(li) => OrderingTerm.asc(li.sortOrder)]))
            .get();
    return rows
        .map(
          (r) => ReceiptLineItem(
            name: r.name,
            priceMyr: r.priceMyr,
            quantity: r.quantity,
            confidence: r.confidence,
          ),
        )
        .toList();
  }

  Future<void> _insertLineItems(
    String transactionId,
    String userId,
    List<ReceiptLineItem> items,
  ) async {
    await _db.batch((batch) {
      batch.insertAll(_db.outboxLineItems, [
        for (var i = 0; i < items.length; i++)
          OutboxLineItemsCompanion.insert(
            id: _uuid.v4(),
            userId: userId,
            transactionId: transactionId,
            name: items[i].name,
            priceMyr: items[i].priceMyr,
            quantity: Value(items[i].quantity),
            confidence: Value(items[i].confidence),
            sortOrder: i,
          ),
      ]);
    });
  }

  /// Shared OCR-derived field encoding for [ingestReceipt] and
  /// [replaceArtifactAndReprocess] — keep both paths in sync.
  ({
    String? merchantCandidatesJson,
    String? llmUnderstandingJson,
    String? cleanedOcrText,
    String? ocrCorrectionsJson,
  }) _encodeOcrSideChannels(IngestReceiptRequest request) {
    return (
      merchantCandidatesJson: request.merchantCandidates.isEmpty
          ? null
          : jsonEncode(
              request.merchantCandidates.map((c) => c.toJson()).toList(),
            ),
      llmUnderstandingJson: request.understanding == null
          ? null
          : jsonEncode(request.understanding!.toJson()),
      cleanedOcrText: request.understanding?.cleanedOcrText,
      ocrCorrectionsJson:
          (request.understanding?.corrections.isEmpty ?? true)
              ? null
              : jsonEncode(
                  request.understanding!.corrections
                      .map((c) => c.toJson())
                      .toList(),
                ),
    );
  }

  /// OCR-derived fields overwritten on retake. User-owned place lock is left
  /// alone unless the confirm sheet newly locked a place. [categoryUser] /
  /// [impactUser] are only written when the confirm sheet supplies them.
  OutboxTransactionsCompanion _ocrDerivedUpdateCompanion(
    IngestReceiptRequest request, {
    required String pipelineStatus,
  }) {
    final amountSource = request.needsAmount ? null : 'ocr';
    final encoded = _encodeOcrSideChannels(request);

    return OutboxTransactionsCompanion(
      amountMyr: Value(request.amountMyr),
      amountSource: Value(amountSource),
      needsAmount: Value(request.needsAmount),
      merchantRaw: Value(request.merchantRaw),
      categoryGuess: Value(request.categoryGuess),
      categoryConfidence: Value(request.categoryConfidence),
      categoryUser: request.categoryUser != null
          ? Value(request.categoryUser)
          : const Value.absent(),
      ocrConfidence: Value(request.ocrConfidence),
      rawOcrText: Value(request.rawOcrText),
      ocrServiceConfidence: Value(request.ocrServiceConfidence),
      lineItemsConfidence: Value(request.lineItemsConfidence),
      parseFailureReason: Value(request.parseFailureReason),
      merchantCandidatesJson: Value(encoded.merchantCandidatesJson),
      ocrHeaderText: Value(request.ocrHeaderText),
      llmUnderstandingJson: Value(encoded.llmUnderstandingJson),
      cleanedOcrText: Value(encoded.cleanedOcrText),
      ocrCorrectionsJson: Value(encoded.ocrCorrectionsJson),
      impactUser: request.impactUser != null
          ? Value(request.impactUser)
          : const Value.absent(),
      placeName: request.pickedPlaceLocked
          ? Value(request.pickedPlaceName)
          : const Value.absent(),
      placeGooglePlaceId: request.pickedPlaceLocked
          ? Value(request.pickedPlaceGooglePlaceId)
          : const Value.absent(),
      placeLat: request.pickedPlaceLocked
          ? Value(request.pickedPlaceLat)
          : const Value.absent(),
      placeLng: request.pickedPlaceLocked
          ? Value(request.pickedPlaceLng)
          : const Value.absent(),
      placeStatus: request.pickedPlaceLocked
          ? const Value('user_locked')
          : const Value.absent(),
      pipelineStatus: Value(pipelineStatus),
      syncStatus: const Value('pending'),
      retryCount: const Value(0),
    );
  }

  TransactionView _mapRow(
    OutboxTransaction row,
    OutboxArtifact? artifact,
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
      localThumbnailPath: artifact?.localFilePath,
      remoteStoragePath: artifact?.storagePath,
      impactUser: row.impactUser,
      lineItems: lineItems,
      rawOcrText: row.rawOcrText,
      ocrConfidence: row.ocrConfidence,
      shareLocationLat: row.shareLocationLat,
      shareLocationLng: row.shareLocationLng,
    );
  }
}
