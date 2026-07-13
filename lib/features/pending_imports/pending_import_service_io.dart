import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/platform/platform_feedback.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/models/pending_import_model.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/transaction_view.dart';
import '../share/receipt_confirm_sheet.dart';
import '../share/receipt_ingest_draft.dart';
import '../share/receipt_ingest_service.dart';

abstract final class PendingImportService {
  static String _resolveUserId() {
    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId != null) return authId;
    if (Env.skipAuth) return 'demo-user';
    return 'demo-user';
  }

  /// Saves the shared file locally and creates a Drift inbox row. No OCR,
  /// no network required. Supabase sync fires in the background.
  static Future<void> saveSharedReceipt({
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
  }

  /// Runs the OCR pipeline on [import] and shows the confirm sheet. On
  /// success the pending import is deleted; on failure or cancel it is kept.
  static Future<void> processImport(
    BuildContext context,
    PendingImportModel import,
  ) async {
    await AppServices.pendingImports.updateStatus(import.id, 'processing');

    PlatformFeedback.lightTap();
    PlatformFeedback.showOcrProgress(context);

    final draft = await _runOcr(context, import);
    if (draft == null) return;

    PlatformFeedback.hideOcrProgress();
    if (!context.mounted) {
      await AppServices.pendingImports.updateStatus(import.id, 'local');
      await ReceiptIngestService.discardDraft(draft);
      return;
    }

    TransactionView? savedTx;

    final categories = await loadBundledCategoryConfig();
    if (!context.mounted) {
      await AppServices.pendingImports.updateStatus(import.id, 'local');
      await ReceiptIngestService.discardDraft(draft);
      return;
    }

    final saved = await ReceiptConfirmSheet.show(
      context,
      draft: draft,
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
        if (tx != null) SocialRepository.createFeedPost(tx);
      },
      onSaveForLater: (editedDraft) async {
        await AppServices.transactions.ingestReceipt(
          editedDraft.toNeedsReviewRequest(),
        );
        // Receipt is now in the review queue — remove from pending inbox.
        await AppServices.pendingImports.delete(import.id);
      },
      onCancel: (cancelledDraft) async {
        // Delete the OCR copy; keep the pending import for retry.
        await ReceiptIngestService.discardDraft(cancelledDraft);
        await AppServices.pendingImports.updateStatus(import.id, 'local');
      },
    );

    if (!saved || savedTx == null) return;

    // Delete the pending import now that a full transaction exists.
    await AppServices.pendingImports.delete(import.id);

    // Best-effort: mark the Supabase pending_receipts row completed.
    final tx = savedTx!;
    unawaited(
      AppServices.pendingImports.markSupabaseCompleted(import.id, tx.id),
    );

    await AppPrefs.setShareCoachMarkPending();

    if (context.mounted) {
      context.pushNamed('ritual');
    }
  }

  static Future<ReceiptIngestDraft?> _runOcr(
    BuildContext context,
    PendingImportModel import,
  ) async {
    try {
      return await ReceiptIngestService.ingestPath(
        path: import.localFilePath,
        mimeType: import.mimeType,
      );
    } catch (e) {
      PlatformFeedback.hideOcrProgress();
      await AppServices.pendingImports.updateStatus(import.id, 'failed');
      if (context.mounted) {
        PlatformFeedback.showError(
          context,
          'Could not read receipt — tap Retry to try again',
        );
      }
      return null;
    }
  }
}
