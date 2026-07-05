import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../local/app_database.dart';

/// Uploads local outbox rows to Supabase Storage + Postgres, then triggers enrichment.
class SyncWorker {
  SyncWorker._();

  static const _maxRetries = 5;

  static Future<void> run(AppDatabase db, String transactionId) async {
    if (!Env.hasSupabaseConfig) return;

    final userId = _resolveUserId();
    if (userId == null) return;

    final row = await (db.select(db.outboxTransactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
    if (row == null) return;
    if (row.syncStatus == 'synced' || row.syncStatus == 'syncing') return;

    final artifact = await (db.select(db.outboxArtifacts)
          ..where((a) => a.transactionId.equals(transactionId)))
        .getSingleOrNull();
    if (artifact == null) return;

    await (db.update(db.outboxTransactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(
      const OutboxTransactionsCompanion(syncStatus: Value('syncing')),
    );

    try {
      final ext = _extensionForMime(artifact.mimeType);
      final storagePath =
          '$userId/${row.id}/${artifact.id}.$ext';

      final file = File(artifact.localFilePath);
      if (!await file.exists()) {
        throw StateError('Artifact file missing');
      }

      await Supabase.instance.client.storage
          .from('receipts')
          .upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: artifact.mimeType,
              upsert: true,
            ),
          );

      await Supabase.instance.client.from('transactions').upsert({
        'id': row.id,
        'user_id': userId,
        'occurred_at': row.occurredAt.toUtc().toIso8601String(),
        'amount_myr': row.amountMyr,
        'amount_source': row.amountSource,
        'needs_amount': row.needsAmount,
        'merchant_raw': row.merchantRaw,
        'category_guess': row.categoryGuess,
        'category_user': row.categoryUser,
        'impact_user': row.impactUser,
        'place_status': row.placeStatus,
        'place_google_place_id': row.placeGooglePlaceId,
        'place_name': row.placeName,
        'place_lat': row.placeLat,
        'place_lng': row.placeLng,
        'share_location_lat': row.shareLocationLat,
        'share_location_lng': row.shareLocationLng,
        'share_location_captured_at':
            row.shareLocationCapturedAt?.toUtc().toIso8601String(),
        'ocr_confidence': row.ocrConfidence,
        'raw_ocr_text': row.rawOcrText,
        'ocr_service_confidence': row.ocrServiceConfidence,
        'line_items_confidence': row.lineItemsConfidence,
        'parse_failure_reason': row.parseFailureReason,
        'pipeline_status': row.pipelineStatus,
      });

      await Supabase.instance.client.from('receipt_artifacts').upsert({
        'id': artifact.id,
        'user_id': userId,
        'transaction_id': row.id,
        'storage_path': storagePath,
        'mime_type': artifact.mimeType,
      });

      final lineItems = await (db.select(db.outboxLineItems)
            ..where((li) => li.transactionId.equals(transactionId)))
          .get();
      if (lineItems.isNotEmpty) {
        await Supabase.instance.client.from('receipt_line_items').upsert([
          for (final li in lineItems)
            {
              'id': li.id,
              'user_id': userId,
              'transaction_id': row.id,
              'name': li.name,
              'price_myr': li.priceMyr,
              'quantity': li.quantity,
              'confidence': li.confidence,
              'sort_order': li.sortOrder,
            },
        ]);
      }

      await (db.update(db.outboxArtifacts)
            ..where((a) => a.id.equals(artifact.id)))
          .write(OutboxArtifactsCompanion(storagePath: Value(storagePath)));

      // Rows awaiting human review are uploaded but not enriched — the edge
      // function would stamp pipeline_status to 'enriched'/'failed_enrichment'
      // and pull the row out of the review queue. Enrichment runs after
      // confirmReview() re-syncs the row as 'provisional'.
      if (row.pipelineStatus != 'needs_review') {
        await Supabase.instance.client.functions.invoke(
          'enrich-transaction',
          body: {'transaction_id': row.id},
        );
      }

      await (db.update(db.outboxTransactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(
        const OutboxTransactionsCompanion(
          syncStatus: Value('synced'),
          lastError: Value(null),
        ),
      );
    } catch (e) {
      final nextRetry = row.retryCount + 1;
      final stuck = nextRetry >= _maxRetries;
      await (db.update(db.outboxTransactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(
        OutboxTransactionsCompanion(
          syncStatus: Value(stuck ? 'stuck' : 'pending'),
          retryCount: Value(nextRetry),
          lastError: Value('$e'),
        ),
      );
    }
  }

  static String? _resolveUserId() {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null) return authId;
    if (Env.skipAuth) return 'demo-user';
    return null;
  }

  static String _extensionForMime(String mime) {
    switch (mime) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'application/pdf':
        return 'pdf';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      default:
        return 'jpg';
    }
  }
}
