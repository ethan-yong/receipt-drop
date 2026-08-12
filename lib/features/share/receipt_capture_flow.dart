import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/ocr_progress_event.dart';
import '../../domain/models/transaction_view.dart';
import 'ocr_progress_notifier.dart';
import 'receipt_capture_menu.dart';
import 'receipt_confirm_sheet.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_ingest_service.dart';
import 'receipt_scan_processing_screen.dart';

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

  static OcrAttemptHandle _startPathAttempt(String path, String mimeType) {
    final notifier = OcrProgressNotifier();
    unawaited(Future<void>(() async {
      try {
        await ReceiptIngestService.ingestPath(
          path: path,
          mimeType: mimeType,
          notifier: notifier,
        );
      } catch (e) {
        await notifier.emit(ProcessingFailedEvent(error: e));
      }
    }));
    return (stream: notifier.stream, dispose: notifier.dispose);
  }

  static OcrAttemptHandle _startBytesAttempt(Uint8List bytes, String mimeType) {
    final notifier = OcrProgressNotifier();
    unawaited(Future<void>(() async {
      try {
        await ReceiptIngestService.ingestBytes(
          bytes: bytes,
          mimeType: mimeType,
          notifier: notifier,
        );
      } catch (e) {
        await notifier.emit(ProcessingFailedEvent(error: e));
      }
    }));
    return (stream: notifier.stream, dispose: notifier.dispose);
  }

  static Future<void> ingestSharedPath(
    BuildContext context, {
    required String path,
    required String mimeType,
  }) async {
    PlatformFeedback.lightTap();
    if (!context.mounted) return;
    final draft = await Navigator.of(context, rootNavigator: true)
        .push<ReceiptIngestDraft>(
      MaterialPageRoute<ReceiptIngestDraft>(
        fullscreenDialog: true,
        builder: (_) => ReceiptScanProcessingScreen(
          attemptFactory: () => _startPathAttempt(path, mimeType),
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    await _showSaveSheet(context, draft);
  }

  static Future<void> _ingestAndSave(
    BuildContext context, {
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final draft = await Navigator.of(context, rootNavigator: true)
        .push<ReceiptIngestDraft>(
      MaterialPageRoute<ReceiptIngestDraft>(
        fullscreenDialog: true,
        builder: (_) => ReceiptScanProcessingScreen(
          attemptFactory: () => _startBytesAttempt(bytes, mimeType),
        ),
      ),
    );
    if (draft == null || !context.mounted) return;
    await _showSaveSheet(context, draft);
  }

  static Future<void> _showSaveSheet(
    BuildContext context,
    ReceiptIngestDraft draft,
  ) async {
    TransactionView? savedTx;

    final categories = await loadBundledCategoryConfig();
    if (!context.mounted) return;

    // ReceiptConfirmSheet reviews and saves in one step now (no separate
    // "edit details" sheet) — true only on a completed save; cancel returns
    // false.
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
      onCancel: ReceiptIngestService.discardDraft,
    );

    if (!saved || savedTx == null || !context.mounted) return;

    context.pushNamed('save-success', extra: <TransactionView>[savedTx!]);
  }
}
