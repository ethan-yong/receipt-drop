import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/transaction_view.dart';
import 'receipt_capture_menu.dart';
import 'receipt_confirm_sheet.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_ingest_service.dart';

/// Picks a receipt, runs ingest, and shows the save sheet.
class ReceiptCaptureFlow {
  ReceiptCaptureFlow._();

  static Future<void> start(BuildContext context) async {
    await ReceiptCaptureMenu.show(
      context,
      onCamera: () => _pickImage(context, ImageSource.camera),
      onGallery: () => _pickImage(context, ImageSource.gallery),
      onFile: () => _pickFile(context),
      onShareHint: () {
        if (context.mounted) context.pushNamed('share-hint');
      },
    );
  }

  static Future<void> _pickImage(
    BuildContext context,
    ImageSource source,
  ) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null || !context.mounted) return;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final mime = file.mimeType ?? 'image/jpeg';
      await _ingestAndSave(context, bytes: bytes, mimeType: mime);
    } catch (e) {
      if (context.mounted) {
        PlatformFeedback.showError(context, 'Could not load image: $e');
      }
    }
  }

  static Future<void> _pickFile(BuildContext context) async {
    try {
      final result = await ReceiptCaptureMenu.pickDocumentFile();
      if (result == null || !context.mounted) return;
      await _ingestAndSave(
        context,
        bytes: result.bytes,
        mimeType: result.mimeType,
      );
    } catch (e) {
      if (context.mounted) {
        PlatformFeedback.showError(context, 'Could not load file: $e');
      }
    }
  }

  static Future<void> ingestSharedPath(
    BuildContext context, {
    required String path,
    required String mimeType,
  }) async {
    try {
      PlatformFeedback.lightTap();
      PlatformFeedback.showOcrProgress(context);
      final draft = await ReceiptIngestService.ingestPath(
        path: path,
        mimeType: mimeType,
      );
      PlatformFeedback.hideOcrProgress();
      if (!context.mounted) return;
      await _showSaveSheet(
        context,
        draft,
        fromShareIntent: true,
      );
    } catch (e) {
      PlatformFeedback.hideOcrProgress();
      if (context.mounted) {
        PlatformFeedback.showError(
          context,
          'Could not read shared receipt: $e',
        );
      }
    }
  }

  static Future<void> _ingestAndSave(
    BuildContext context, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    PlatformFeedback.showOcrProgress(context);
    try {
      final draft = await ReceiptIngestService.ingestBytes(
        bytes: bytes,
        mimeType: mimeType,
      );
      PlatformFeedback.hideOcrProgress();
      if (!context.mounted) return;
      await _showSaveSheet(context, draft);
    } catch (e) {
      PlatformFeedback.hideOcrProgress();
      if (context.mounted) {
        PlatformFeedback.showError(context, 'Could not read receipt: $e');
      }
    }
  }

  static Future<void> _showSaveSheet(
    BuildContext context,
    ReceiptIngestDraft draft, {
    bool fromShareIntent = false,
  }) async {
    TransactionView? savedTx;

    final categories = await loadBundledCategoryConfig();
    if (!context.mounted) return;

    // ReceiptConfirmSheet reviews and saves in one step now (no separate
    // "edit details" sheet) — true only on a completed save; cancel and
    // "save for later" both return false.
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
      // Parks the receipt in the review queue (no ritual, no feed post) —
      // closing the "cancel = receipt lost" hole for unreadable receipts.
      onSaveForLater: (editedDraft) async {
        await AppServices.transactions.ingestReceipt(
          editedDraft.toNeedsReviewRequest(),
        );
      },
      onCancel: ReceiptIngestService.discardDraft,
    );

    if (!saved || savedTx == null || !context.mounted) return;

    if (fromShareIntent) {
      await AppPrefs.setShareCoachMarkPending();
    }

    if (!context.mounted) return;

    context.pushNamed('ritual');
  }
}
