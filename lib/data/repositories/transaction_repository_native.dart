import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
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
import 'insights_worker.dart';
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
            occurredAt: Value(request.occurredAt ?? now),
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
              _hasResolvedPlace(request) ? request.pickedPlaceName : null,
            ),
            placeGooglePlaceId: Value(
              _hasResolvedPlace(request)
                  ? request.pickedPlaceGooglePlaceId
                  : null,
            ),
            placeLat: Value(
              _hasResolvedPlace(request) ? request.pickedPlaceLat : null,
            ),
            placeLng: Value(
              _hasResolvedPlace(request) ? request.pickedPlaceLng : null,
            ),
            placeStatus: Value(_placeStatusFor(request)),
            notes: Value(request.notes),
          ),
        );

    // Artifact-less transactions (e.g. captured from a payment notification,
    // no receipt image) are a supported state — SyncWorker.run treats a
    // missing outbox_artifacts row as "nothing to upload", not "not synced".
    final localFilePath = request.localFilePath;
    final mimeType = request.mimeType;
    if (localFilePath != null && mimeType != null) {
      await _db
          .into(_db.outboxArtifacts)
          .insert(
            OutboxArtifactsCompanion.insert(
              id: artifactId,
              userId: request.userId,
              transactionId: id,
              mimeType: mimeType,
              localFilePath: localFilePath,
            ),
          );
    }

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

    final row = await (_db.select(_db.outboxTransactions)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    final artifact = await _artifactFor(id);
    final lineItems = await _lineItemsFor(id);
    return _mapRow(row, artifact, lineItems);
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

      // A retake always supplies a real file — this method's contract
      // ("always leaves exactly one outbox_artifacts row") predates and is
      // unaffected by the artifact-less-transaction support added to
      // ingestReceipt above; asserting non-null here just documents that.
      await _db
          .into(_db.outboxArtifacts)
          .insert(
            OutboxArtifactsCompanion.insert(
              id: newArtifactId,
              userId: request.userId.isEmpty ? existing.userId : request.userId,
              transactionId: transactionId,
              mimeType: request.mimeType!,
              localFilePath: request.localFilePath!,
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
        syncStatus: const Value('pending'),
        retryCount: const Value(0),
      ),
    );
    final items = view.lineItems;
    if (items != null) {
      for (final item in items) {
        final id = item.id;
        if (id == null || id.isEmpty) continue;
        await (_db.update(_db.outboxLineItems)..where((li) => li.id.equals(id)))
            .write(
          OutboxLineItemsCompanion(
            name: Value(item.name),
            priceMyr: Value(item.priceMyr),
            quantity: Value(item.quantity),
          ),
        );
      }
    }
    unawaited(SyncWorker.run(_db, view.id));
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

  /// Restores this user's cloud data into a local database that has nothing
  /// for them yet — a fresh install (or a cleared local cache) otherwise
  /// leaves the account signed in with no visible history, even though the
  /// data is intact in Supabase, because every screen here reads only from
  /// the local outbox and [SyncWorker] only ever pushes local -> cloud.
  ///
  /// Safe to call on every sign-in event with no separate "already
  /// hydrated" flag: it no-ops the instant this user has any local rows at
  /// all (including right after its own first successful run), and it
  /// naturally re-runs correctly if local data is later cleared again.
  /// Best-effort — any failure (offline, transient error) is swallowed so a
  /// bad network moment can never crash startup; the next sign-in event or
  /// launch gets another chance.
  Future<void> hydrateFromCloudIfEmpty(String userId) async {
    debugPrint('hydrateFromCloudIfEmpty: called for userId=$userId');
    if (!Env.hasSupabaseConfig) {
      debugPrint('hydrateFromCloudIfEmpty: no Supabase config, skipping');
      return;
    }

    final existing = await (_db.select(
      _db.outboxTransactions,
    )..where((t) => t.userId.equals(userId))).get();
    if (existing.isNotEmpty) {
      debugPrint(
        'hydrateFromCloudIfEmpty: ${existing.length} local rows already exist for this userId, skipping',
      );
      return;
    }

    try {
      final client = Supabase.instance.client;
      // Bounded, most-recent-first — restoring a user's entire history
      // unbounded isn't needed for the app to become usable again; mirrors
      // the map viewport RPC's own precedent of an explicit cap rather than
      // an unbounded query.
      final remoteTx = await client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('occurred_at', ascending: false)
          .limit(500) as List;
      debugPrint('hydrateFromCloudIfEmpty: fetched ${remoteTx.length} remote rows');
      if (remoteTx.isEmpty) return;

      final txIds = [
        for (final row in remoteTx) (row as Map<String, dynamic>)['id'] as String,
      ];

      final remoteArtifacts = await client
          .from('receipt_artifacts')
          .select()
          .inFilter('transaction_id', txIds) as List;
      final remoteLineItems = await client
          .from('receipt_line_items')
          .select()
          .inFilter('transaction_id', txIds) as List;

      String? encodeJson(Object? value) => value == null ? null : jsonEncode(value);
      double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();

      await _db.batch((batch) {
        batch.insertAll(_db.outboxTransactions, [
          for (final r in remoteTx.cast<Map<String, dynamic>>())
            OutboxTransactionsCompanion.insert(
              id: r['id'] as String,
              userId: userId,
              createdAt: Value(DateTime.parse(r['created_at'] as String)),
              occurredAt: Value(DateTime.parse(r['occurred_at'] as String)),
              amountMyr: Value(asDouble(r['amount_myr'])),
              amountSource: Value(r['amount_source'] as String?),
              needsAmount: Value(r['needs_amount'] as bool? ?? false),
              merchantRaw: Value(r['merchant_raw'] as String?),
              merchantNormalized: Value(r['merchant_normalized'] as String?),
              categoryGuess: Value(r['category_guess'] as String?),
              categoryUser: Value(r['category_user'] as String?),
              categoryConfidence: Value(asDouble(r['category_confidence'])),
              impactUser: Value(r['impact_user'] as String?),
              placeStatus: Value(r['place_status'] as String? ?? 'none'),
              placeGooglePlaceId: Value(r['place_google_place_id'] as String?),
              placeName: Value(r['place_name'] as String?),
              placeLat: Value(asDouble(r['place_lat'])),
              placeLng: Value(asDouble(r['place_lng'])),
              placeConfidence: Value(asDouble(r['place_confidence'])),
              shareLocationLat: Value(asDouble(r['share_location_lat'])),
              shareLocationLng: Value(asDouble(r['share_location_lng'])),
              shareLocationCapturedAt: Value(
                r['share_location_captured_at'] == null
                    ? null
                    : DateTime.parse(r['share_location_captured_at'] as String),
              ),
              ocrConfidence: Value(asDouble(r['ocr_confidence'])),
              rawOcrText: Value(r['raw_ocr_text'] as String?),
              ocrServiceConfidence: Value(asDouble(r['ocr_service_confidence'])),
              lineItemsConfidence: Value(asDouble(r['line_items_confidence'])),
              parseFailureReason: Value(r['parse_failure_reason'] as String?),
              pipelineStatus: Value(r['pipeline_status'] as String? ?? 'provisional'),
              merchantCandidatesJson: Value(encodeJson(r['merchant_candidates'])),
              ocrHeaderText: Value(r['ocr_header_text'] as String?),
              llmUnderstandingJson: Value(encodeJson(r['llm_understanding'])),
              cleanedOcrText: Value(r['cleaned_ocr_text'] as String?),
              ocrCorrectionsJson: Value(encodeJson(r['ocr_corrections'])),
              // Local-only bookkeeping, no remote counterpart: this row is
              // already on the server, so it's synced by definition.
              syncStatus: const Value('synced'),
              retryCount: const Value(0),
            ),
        ]);

        batch.insertAll(_db.outboxArtifacts, [
          for (final r in remoteArtifacts.cast<Map<String, dynamic>>())
            OutboxArtifactsCompanion.insert(
              id: r['id'] as String,
              userId: userId,
              transactionId: r['transaction_id'] as String,
              storagePath: Value(r['storage_path'] as String?),
              mimeType: r['mime_type'] as String,
              // No on-device file exists for a hydrated row — this
              // deliberately never resolves via File(...).existsSync(), so
              // display code already falls back to the signed-URL path
              // built for exactly this "local file missing" case.
              localFilePath: '',
            ),
        ]);

        batch.insertAll(_db.outboxLineItems, [
          for (final r in remoteLineItems.cast<Map<String, dynamic>>())
            OutboxLineItemsCompanion.insert(
              id: r['id'] as String,
              userId: userId,
              transactionId: r['transaction_id'] as String,
              name: r['name'] as String,
              priceMyr: (r['price_myr'] as num).toDouble(),
              quantity: Value(r['quantity'] as int?),
              confidence: Value(asDouble(r['confidence'])),
              sortOrder: r['sort_order'] as int,
            ),
        ]);
      });
      debugPrint('hydrateFromCloudIfEmpty: batch insert succeeded');

      // Seed / restore paths often have transactions but no local receipt
      // files, so editing one cannot run SyncWorker (no artifact). Run insight
      // detectors on the hydrated rows directly instead.
      unawaited(InsightsWorker.noteSyncedTransaction());
      unawaited(
        InsightsWorker.run(
          _db,
          loadTransactions: _loadTransactionViewsForInsights,
        ),
      );
    } on Object catch (e, st) {
      // Offline / transient failure — the empty-check above means the next
      // sign-in event or app launch gets another chance.
      debugPrint('TransactionRepository.hydrateFromCloudIfEmpty: $e\n$st');
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
            id: r.id,
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
      placeName: _hasResolvedPlace(request)
          ? Value(request.pickedPlaceName)
          : const Value.absent(),
      placeGooglePlaceId: _hasResolvedPlace(request)
          ? Value(request.pickedPlaceGooglePlaceId)
          : const Value.absent(),
      placeLat: _hasResolvedPlace(request)
          ? Value(request.pickedPlaceLat)
          : const Value.absent(),
      placeLng: _hasResolvedPlace(request)
          ? Value(request.pickedPlaceLng)
          : const Value.absent(),
      placeStatus: _hasResolvedPlace(request)
          ? Value(_placeStatusFor(request))
          : const Value.absent(),
      pipelineStatus: Value(pipelineStatus),
      syncStatus: const Value('pending'),
      retryCount: const Value(0),
    );
  }

  static bool _hasResolvedPlace(IngestReceiptRequest request) =>
      request.pickedPlaceLat != null && request.pickedPlaceLng != null;

  static String _placeStatusFor(IngestReceiptRequest request) {
    if (request.pickedPlaceLocked) return 'user_locked';
    if (_hasResolvedPlace(request)) return 'guess';
    return 'none';
  }

  /// Lightweight load for insight detectors — no artifact/line-item joins.
  Future<List<TransactionView>> _loadTransactionViewsForInsights() async {
    final rows = await (_db.select(_db.outboxTransactions)
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]))
        .get();
    return [
      for (final row in rows)
        TransactionView(
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
          impactUser: row.impactUser,
          ocrConfidence: row.ocrConfidence,
          categoryConfidence: row.categoryConfidence,
          shareLocationLat: row.shareLocationLat,
          shareLocationLng: row.shareLocationLng,
        ),
    ];
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
      categoryConfidence: row.categoryConfidence,
      shareLocationLat: row.shareLocationLat,
      shareLocationLng: row.shareLocationLng,
    );
  }
}
