import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/platform/platform_feedback.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/models/ocr_progress_event.dart';
import 'ocr_progress_notifier.dart';
import 'receipt_capture_menu.dart';
import 'receipt_confirm_sheet.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_ingest_service.dart';
import 'receipt_scan_processing_screen.dart';

/// Retake path for an existing transaction: capture → OCR → confirm sheet,
/// then [TransactionRepository.replaceArtifactAndReprocess] on Save.
///
/// Reuses [ReceiptConfirmSheet] unmodified via callback injection. A cancel
/// or failed OCR leaves the original artifact untouched (decision 5).
class ReceiptRetakeFlow {
  ReceiptRetakeFlow._();

  /// Returns `true` when the user confirmed a successful retake.
  static Future<bool> start(
    BuildContext context, {
    required String transactionId,
  }) async {
    var started = false;
    final completer = Completer<bool>();

    Future<void> run(Future<bool> Function() work) async {
      started = true;
      try {
        completer.complete(await work());
      } catch (_) {
        if (!completer.isCompleted) completer.complete(false);
      }
    }

    await ReceiptCaptureMenu.show(
      context,
      onCamera: () {
        unawaited(run(
          () => _pickImage(
            context,
            ImageSource.camera,
            transactionId: transactionId,
          ),
        ));
      },
      onGallery: () {
        unawaited(run(
          () => _pickImage(
            context,
            ImageSource.gallery,
            transactionId: transactionId,
          ),
        ));
      },
      onFile: () {
        unawaited(run(
          () => _pickFile(context, transactionId: transactionId),
        ));
      },
      // Share-from-another-app isn't a retake path — treat as cancel.
      onShareHint: () {},
    );

    if (!started) return false;
    return completer.future;
  }

  static Future<bool> _pickImage(
    BuildContext context,
    ImageSource source, {
    required String transactionId,
  }) async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null || !context.mounted) return false;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return false;
      final mime = file.mimeType ?? 'image/jpeg';
      return _processAndConfirm(
        context,
        bytes: bytes,
        mimeType: mime,
        transactionId: transactionId,
      );
    } catch (e) {
      if (context.mounted) {
        PlatformFeedback.showError(context, 'Could not load image: $e');
      }
      return false;
    }
  }

  static Future<bool> _pickFile(
    BuildContext context, {
    required String transactionId,
  }) async {
    try {
      final result = await ReceiptCaptureMenu.pickDocumentFile();
      if (result == null || !context.mounted) return false;
      return _processAndConfirm(
        context,
        bytes: result.bytes,
        mimeType: result.mimeType,
        transactionId: transactionId,
      );
    } catch (e) {
      if (context.mounted) {
        PlatformFeedback.showError(context, 'Could not load file: $e');
      }
      return false;
    }
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

  static Future<bool> _processAndConfirm(
    BuildContext context, {
    required Uint8List bytes,
    required String mimeType,
    required String transactionId,
  }) async {
    // OCR failure / back-out returns null — original transaction untouched.
    final draft = await Navigator.of(context, rootNavigator: true)
        .push<ReceiptIngestDraft>(
      MaterialPageRoute<ReceiptIngestDraft>(
        fullscreenDialog: true,
        builder: (_) => ReceiptScanProcessingScreen(
          attemptFactory: () => _startBytesAttempt(bytes, mimeType),
        ),
      ),
    );
    if (draft == null || !context.mounted) return false;
    return _showConfirmSheet(
      context,
      draft: draft,
      transactionId: transactionId,
    );
  }

  static Future<bool> _showConfirmSheet(
    BuildContext context, {
    required ReceiptIngestDraft draft,
    required String transactionId,
  }) async {
    final categories = await loadBundledCategoryConfig();
    if (!context.mounted) return false;

    var didReplace = false;
    final saved = await ReceiptConfirmSheet.show(
      context,
      draft: draft,
      categories: categories,
      onSave: (amount, editedDraft, impact) async {
        if (amount == null) return;
        await AppServices.transactions.replaceArtifactAndReprocess(
          transactionId,
          editedDraft.toIngestRequest(
            confirmedAmount: amount,
            impactUser: impact.name,
          ),
        );
        didReplace = true;
      },
      onSaveForLater: (editedDraft) async {
        await AppServices.transactions.replaceArtifactAndReprocess(
          transactionId,
          editedDraft.toNeedsReviewRequest(),
        );
        didReplace = true;
      },
      // Discards only the newly captured local file — original untouched.
      onCancel: ReceiptIngestService.discardDraft,
    );

    return saved && didReplace;
  }
}
