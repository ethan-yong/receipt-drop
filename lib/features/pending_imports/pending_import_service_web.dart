import 'package:flutter/material.dart';

import '../../domain/models/pending_import_model.dart';
import '../share/batch_scan_progress.dart';

abstract final class PendingImportService {
  static Future<void> saveSharedReceipt({
    required String path,
    required String mimeType,
    String? sourceApp,
  }) async {
    throw UnsupportedError('Pending imports are not supported on web');
  }

  static Future<ProcessImportResult> processImport(
    BuildContext context,
    PendingImportModel import, {
    BatchScanProgress? batchProgress,
    bool deferSaveSuccessNav = false,
  }) async {
    throw UnsupportedError('Pending imports are not supported on web');
  }
}
