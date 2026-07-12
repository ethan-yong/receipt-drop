import 'package:flutter/material.dart';

import '../../domain/models/pending_import_model.dart';

abstract final class PendingImportService {
  static Future<void> saveSharedReceipt({
    required String path,
    required String mimeType,
    String? sourceApp,
  }) async {
    throw UnsupportedError('Pending imports are not supported on web');
  }

  static Future<void> processImport(
    BuildContext context,
    PendingImportModel import,
  ) async {
    throw UnsupportedError('Pending imports are not supported on web');
  }
}
