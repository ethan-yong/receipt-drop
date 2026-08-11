import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/utils/current_location.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/ocr_progress_event.dart';
import '../../domain/models/pending_import_model.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/transaction_view.dart';
import '../share/batch_scan_progress.dart';
import '../share/ocr_progress_notifier.dart';
import '../share/receipt_confirm_sheet.dart';
import '../share/receipt_ingest_draft.dart';
import '../share/receipt_ingest_service.dart';
import '../share/receipt_scan_processing_screen.dart';

abstract final class PendingImportService {
  static String _resolveUserId() {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null) return authId;
    if (Env.skipAuth) return 'demo-user';
    return 'demo-user';
  }

  /// Saves the shared file locally and creates a Drift inbox row. No OCR,
  /// no network required. Supabase sync fires in the background. Returns
  /// the created row so the caller (the share-intent listener) can key the
  /// post-share notification to it.
  static Future<PendingImportModel> saveSharedReceipt({
    required String path,
    required String mimeType,
    String? sourceApp,
  }) async {
    final userId = _resolveUserId();
    final import = await AppServices.pendingImports.create(
      userId: userId,
      sourcePath: path,
      mimeType: mimeType,
      sourceApp: sourceApp,
    );
    unawaited(AppServices.pendingImports.syncToSupabase(import));
    return import;
  }

  /// Best-effort: resolves a share-time GPS fix to a nearby-venue name and
  /// writes it onto [import]'s row for the pending-imports card to display.
  /// Every failure mode (no permission, no fix, no nearby match, network
  /// error) is swallowed here — this must never surface to the caller or
  /// affect anything else in the share flow. See
  /// `docs/plans/2026-07-30-pending-receipt-location-context.md`.
  static Future<void> resolveLocationBestEffort(
    PendingImportModel import,
  ) async {
    try {
      final position = await getCurrentPositionPassiveOrNull();
      if (position == null) return;

      final candidates = await PlacesRepository.fetchNearbyCandidates(
        lat: position.latitude,
        lng: position.longitude,
        limit: 1,
      );
      if (candidates.isEmpty) return;

      final name = candidates.first.name.trim();
      if (name.isEmpty) return;

      await AppServices.pendingImports.setVenueLabel(import.id, name);
    } on Object {
      // Best-effort only — never a dependency for the rest of the flow.
    }
  }

  /// Runs the OCR pipeline on [import] via the animated processing screen,
  /// then shows the confirm sheet. On success the pending import is
  /// deleted; on failure or cancel it is kept.
  ///
  /// When part of a "Process all" batch, [batchProgress] threads the
  /// running completed-count/names through so the processing screen's
  /// footer stays accurate across the sequence, returned in the result's
  /// `progress` field for the caller to pass into the next call in the loop.
  ///
  /// By default a successful save navigates straight to the save-success
  /// screen. Pass [deferSaveSuccessNav] true to suppress that (e.g. a batch
  /// loop that wants to show one consolidated celebration at the end
  /// instead of one per receipt) — the saved transaction is always
  /// returned in the result's `savedTx` field so the caller can collect it.
  static Future<ProcessImportResult> processImport(
    BuildContext context,
    PendingImportModel import, {
    BatchScanProgress? batchProgress,
    bool deferSaveSuccessNav = false,
  }) async {
    await AppServices.pendingImports.updateStatus(import.id, 'processing');
    var savedSuccessfully = false;
    try {
      if (!context.mounted) {
        return (progress: batchProgress, savedTx: null);
      }
      PlatformFeedback.lightTap();

      OcrAttemptHandle startAttempt() {
        final notifier = OcrProgressNotifier();
        unawaited(Future<void>(() async {
          try {
            await ReceiptIngestService.ingestPath(
              path: import.localFilePath,
              mimeType: import.mimeType,
              notifier: notifier,
            );
          } catch (e) {
            await AppServices.pendingImports.updateStatus(import.id, 'failed');
            await notifier.emit(ProcessingFailedEvent(error: e));
          }
        }));
        return (stream: notifier.stream, dispose: notifier.dispose);
      }

      final draft = await Navigator.of(context, rootNavigator: true)
          .push<ReceiptIngestDraft>(
        MaterialPageRoute<ReceiptIngestDraft>(
          fullscreenDialog: true,
          builder: (_) => ReceiptScanProcessingScreen(
            attemptFactory: startAttempt,
            batchProgress: batchProgress,
          ),
        ),
      );
      // Back from the OCR screen — leave the inbox row for a later retry.
      if (draft == null) return (progress: batchProgress, savedTx: null);

      // Carry through a note attached earlier via the post-share
      // notification's inline reply — the confirm sheet prefills it so it
      // isn't lost between the notification and the user actually opening
      // this import.
      final draftWithNote =
          import.note != null ? draft.copyWith(notes: import.note) : draft;

      if (!context.mounted) {
        await ReceiptIngestService.discardDraft(draft);
        return (progress: batchProgress, savedTx: null);
      }

      TransactionView? savedTx;
      var completedThisReceipt = false;

      final categories = await loadBundledCategoryConfig();
      if (!context.mounted) {
        await ReceiptIngestService.discardDraft(draft);
        return (progress: batchProgress, savedTx: null);
      }

      final saved = await ReceiptConfirmSheet.show(
        context,
        draft: draftWithNote,
        categories: categories,
        onSave: (amount, editedDraft, impact) async {
          if (amount == null) return;
          savedTx = await AppServices.transactions.ingestReceipt(
            editedDraft.toIngestRequest(
              confirmedAmount: amount,
              impactUser: impact.name,
            ),
          );
          final tx = savedTx;
          if (tx != null) {
            SocialRepository.createFeedPost(tx);
            completedThisReceipt = true;
          }
        },
        onCancel: (cancelledDraft) async {
          // Delete the OCR copy; keep the pending import for retry.
          await ReceiptIngestService.discardDraft(cancelledDraft);
          await AppServices.pendingImports.updateStatus(import.id, 'local');
        },
      );

      final nextProgress = completedThisReceipt
          ? batchProgress?.withCompleted(draft.merchantRaw ?? 'Receipt')
          : batchProgress;

      if (!saved || savedTx == null) {
        // Cancel already discarded + reset. System-back / barrier dismiss
        // skips onCancel — clean up the OCR copy and unlock the card here.
        await ReceiptIngestService.discardDraft(draftWithNote);
        return (progress: nextProgress, savedTx: null);
      }

      // Delete the pending import now that a full transaction exists.
      await AppServices.pendingImports.delete(import.id);
      savedSuccessfully = true;

      // Best-effort: mark the Supabase pending_receipts row completed.
      final tx = savedTx!;
      unawaited(
        AppServices.pendingImports.markSupabaseCompleted(import.id, tx.id),
      );

      await AppPrefs.setShareCoachMarkPending();

      if (context.mounted && !deferSaveSuccessNav) {
        context.pushNamed('save-success', extra: [tx]);
      }
      return (progress: nextProgress, savedTx: tx);
    } finally {
      // Unlock any row still marked `processing`. Does not clobber `failed`
      // (OCR error) or a row already deleted after a successful save.
      if (!savedSuccessfully) {
        await AppServices.pendingImports.resetToLocalIfProcessing(import.id);
      }
    }
  }
}
