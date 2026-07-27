import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/utils/text_normalize.dart';
import '../../domain/logic/misread_pattern_extractor.dart';
import '../../domain/models/field_correction.dart';
import '../local/app_database.dart';

/// Maps a partial remote `transactions` row (as returned by a `select(...)`
/// call) into an [OutboxTransactionsCompanion] patch — the fields
/// `enrich-transaction` writes server-side, applied back to the local
/// outbox. Pure/testable: doesn't touch Supabase or the database itself.
OutboxTransactionsCompanion buildEnrichmentCompanion(
  Map<String, dynamic> remoteRow,
) {
  double? asDouble(Object? v) => v == null ? null : (v as num).toDouble();
  return OutboxTransactionsCompanion(
    placeName: Value(remoteRow['place_name'] as String?),
    placeGooglePlaceId: Value(remoteRow['place_google_place_id'] as String?),
    placeLat: Value(asDouble(remoteRow['place_lat'])),
    placeLng: Value(asDouble(remoteRow['place_lng'])),
    placeConfidence: Value(asDouble(remoteRow['place_confidence'])),
    placeStatus: Value(remoteRow['place_status'] as String? ?? 'none'),
    merchantNormalized: Value(remoteRow['merchant_normalized'] as String?),
    pipelineStatus:
        Value(remoteRow['pipeline_status'] as String? ?? 'provisional'),
  );
}

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
        // Was missing entirely — enrich-transaction's category-biased
        // Nearby Search (`category_confidence >= 0.5`) always saw a stale
        // null/0 without this, silently falling back to generic place types.
        'category_confidence': row.categoryConfidence,
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
        'merchant_candidates': row.merchantCandidatesJson == null
            ? null
            : jsonDecode(row.merchantCandidatesJson!),
        'ocr_header_text': row.ocrHeaderText,
        // Lets enrich-transaction skip its own LLM call — the client already
        // ran OCR + LLM understanding synchronously at capture time (see
        // docs/decisions.md).
        'llm_understanding': row.llmUnderstandingJson == null
            ? null
            : jsonDecode(row.llmUnderstandingJson!),
        // LLM OCR-cleanup step's corrected transcript (opt-in server-side
        // via LLM_CLEANUP_ENABLED) — additive alongside, never replacing,
        // raw_ocr_text above. Usually null (feature defaults off / no
        // correction accepted).
        'cleaned_ocr_text': row.cleanedOcrText,
        'ocr_corrections': row.ocrCorrectionsJson == null
            ? null
            : jsonDecode(row.ocrCorrectionsJson!),
      });

      await Supabase.instance.client.from('receipt_artifacts').upsert({
        'id': artifact.id,
        'user_id': userId,
        'transaction_id': row.id,
        'storage_path': storagePath,
        'mime_type': artifact.mimeType,
      });

      // Single-version semantics: after a retake, any older remote artifact
      // rows for this transaction are superseded. Clean them up here (async
      // relative to the local replace) so Storage stays bounded.
      await _cleanupSupersededRemoteArtifacts(
        transactionId: row.id,
        keepArtifactId: artifact.id,
      );

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

      // Field corrections must land before enrich-transaction runs below —
      // its merchant-alias write-back (see
      // docs/plans/2026-07-23-feedback-learning-system.md) reads this
      // transaction's pending corrections from `user_field_corrections`.
      final pendingCorrections = await (db.select(db.outboxFieldCorrections)
            ..where(
              (c) =>
                  c.transactionId.equals(transactionId) &
                  c.syncStatus.equals('pending'),
            ))
          .get();
      if (pendingCorrections.isNotEmpty) {
        await Supabase.instance.client.from('user_field_corrections').upsert([
          for (final c in pendingCorrections)
            {
              'id': c.id,
              'user_id': userId,
              'transaction_id': row.id,
              'field': c.field,
              'predicted_value': c.predictedValue,
              'confirmed_value': c.confirmedValue,
              'merchant_raw': c.merchantRaw,
              'confidence': c.confidence,
              'correction_type': c.correctionType,
              'line_item_index': c.lineItemIndex,
              'created_at': c.createdAt.toUtc().toIso8601String(),
            },
        ]);

        // Category preference + OCR-misread-pattern consumption: both are
        // "online/immediate" per the feature's online/offline treatment —
        // a running counter updated at write time, no batch job required.
        // Best-effort per correction: a missed update here never blocks the
        // transaction's own sync, which has already succeeded above.
        for (final c in pendingCorrections) {
          if (c.field == FieldCorrection.fieldCategory) {
            final merchant = c.merchantRaw?.trim();
            if (merchant != null && merchant.isNotEmpty) {
              try {
                await Supabase.instance.client.rpc(
                  'upsert_category_preference',
                  params: {
                    'p_merchant_normalized': normalizeForCompare(merchant),
                    'p_category': c.confirmedValue,
                  },
                );
              } catch (_) {
                // Next correction to the same merchant will retry the gate.
              }
            }
          } else if (c.field == FieldCorrection.fieldAmount ||
              c.field == FieldCorrection.fieldLineItemPrice) {
            // Abstraction already happened client-side — the actual amount
            // never appears past this point, only the character classes.
            final patterns =
                extractMisreadPatterns(c.predictedValue, c.confirmedValue);
            for (final p in patterns) {
              try {
                await Supabase.instance.client.rpc(
                  'upsert_misread_pattern',
                  params: {
                    'p_from_char': p.fromChar,
                    'p_to_char': p.toChar,
                  },
                );
              } catch (_) {
                // Non-fatal — a missed aggregation count is not correctness-
                // critical for any single transaction's own sync.
              }
            }
          }
        }

        await (db.update(db.outboxFieldCorrections)
              ..where((c) => c.transactionId.equals(transactionId)))
            .write(
          const OutboxFieldCorrectionsCompanion(syncStatus: Value('synced')),
        );
      }

      // Rows awaiting human review are uploaded but not enriched — the edge
      // function would stamp pipeline_status to 'enriched'/'failed_enrichment'
      // and pull the row out of the review queue. Enrichment runs after
      // confirmReview() re-syncs the row as 'provisional'.
      if (row.pipelineStatus != 'needs_review') {
        await Supabase.instance.client.functions.invoke(
          'enrich-transaction',
          body: {'transaction_id': row.id},
        );

        // enrich-transaction updates Postgres directly; nothing in the
        // invoke call above writes those fields back to the local outbox.
        // Re-fetch and apply them so the UI shows the enriched place name
        // instead of raw OCR text without waiting for a full re-sync.
        // Best-effort: enrichment already succeeded server-side regardless
        // of whether this read-back works.
        try {
          final refreshed = await Supabase.instance.client
              .from('transactions')
              .select(
                'place_name, place_google_place_id, place_lat, place_lng, '
                'place_confidence, place_status, merchant_normalized, '
                'pipeline_status',
              )
              .eq('id', row.id)
              .maybeSingle();
          if (refreshed != null) {
            await (db.update(db.outboxTransactions)
                  ..where((t) => t.id.equals(transactionId)))
                .write(buildEnrichmentCompanion(refreshed));
          }
        } catch (_) {
          // Next sync (or a manual retry) will pick this up.
        }
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

  /// Deletes remote `receipt_artifacts` (and their Storage objects) that are
  /// no longer the current artifact for [transactionId] — typically left
  /// behind by a confirmed retake's local replace.
  static Future<void> _cleanupSupersededRemoteArtifacts({
    required String transactionId,
    required String keepArtifactId,
  }) async {
    try {
      final stale = await Supabase.instance.client
          .from('receipt_artifacts')
          .select('id, storage_path')
          .eq('transaction_id', transactionId)
          .neq('id', keepArtifactId);
      for (final row in stale) {
        final id = row['id'] as String?;
        final path = row['storage_path'] as String?;
        if (path != null && path.isNotEmpty) {
          try {
            await Supabase.instance.client.storage
                .from('receipts')
                .remove([path]);
          } catch (_) {
            // Best-effort — orphan Storage objects stay owner-scoped via RLS.
          }
        }
        if (id != null) {
          try {
            await Supabase.instance.client
                .from('receipt_artifacts')
                .delete()
                .eq('id', id);
          } catch (_) {
            // Retry on a later sync if this fails.
          }
        }
      }
    } catch (_) {
      // Non-fatal: next successful sync for this transaction retries cleanup.
    }
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
