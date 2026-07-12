import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/config/env.dart';
import '../../domain/models/pending_import_model.dart';
import '../local/app_database.dart';

class PendingImportsRepository {
  PendingImportsRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Stream<List<PendingImportModel>> watchAll() {
    return (_db.select(_db.pendingImports)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  /// Saves a file to the on-device pending_receipts directory and writes a
  /// Drift row. Returns the new [PendingImportModel] immediately — no network call.
  Future<PendingImportModel> create({
    required String userId,
    required String sourcePath,
    required String mimeType,
    String? sourceApp,
  }) async {
    final id = _uuid.v4();
    final destPath = await _copyToPendingDir(sourcePath, id, mimeType);

    await _db.into(_db.pendingImports).insert(
          PendingImportsCompanion.insert(
            id: id,
            userId: userId,
            localFilePath: destPath,
            mimeType: mimeType,
            sourceApp: Value(sourceApp),
            status: const Value('local'),
          ),
        );

    final row = await (_db.select(_db.pendingImports)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    return _toModel(row);
  }

  Future<void> updateStatus(String id, String status) async {
    await (_db.update(_db.pendingImports)..where((t) => t.id.equals(id)))
        .write(PendingImportsCompanion(status: Value(status)));
  }

  /// Deletes the Drift row and the local file. Called only after a successful
  /// transaction save — not on failure or cancel.
  Future<void> delete(String id) async {
    final row = await (_db.select(_db.pendingImports)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;

    await (_db.delete(_db.pendingImports)..where((t) => t.id.equals(id))).go();

    try {
      final file = File(row.localFilePath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Uploads the local file to the `receipts` bucket and inserts a
  /// `pending_receipts` row in Supabase. Best-effort — caller should
  /// `unawaited()` this and treat failures as non-fatal.
  Future<void> syncToSupabase(PendingImportModel import) async {
    if (!Env.hasSupabaseConfig) return;

    final authId = Supabase.instance.client.auth.currentUser?.id;
    if (authId == null) return;

    try {
      final ext = _extForMime(import.mimeType);
      final storagePath = '$authId/pending/${import.id}.$ext';

      final file = File(import.localFilePath);
      if (!await file.exists()) return;

      await Supabase.instance.client.storage.from('receipts').upload(
            storagePath,
            file,
            fileOptions: FileOptions(
              contentType: import.mimeType,
              upsert: true,
            ),
          );

      await Supabase.instance.client.from('pending_receipts').upsert({
        'id': import.id,
        'user_id': authId,
        'storage_path': storagePath,
        'file_type': import.mimeType,
        'status': 'pending',
        if (import.sourceApp != null) 'source_app': import.sourceApp,
        'created_at': import.createdAt.toUtc().toIso8601String(),
      });
    } catch (e) {
      debugPrint('PendingImportsRepository.syncToSupabase: $e');
    }
  }

  /// Updates the cloud `pending_receipts` row to `completed` and links the
  /// new transaction. Best-effort — caller should not await the result.
  Future<void> markSupabaseCompleted(String id, String transactionId) async {
    if (!Env.hasSupabaseConfig) return;
    if (Supabase.instance.client.auth.currentUser == null) return;

    try {
      await Supabase.instance.client
          .from('pending_receipts')
          .update({'status': 'completed', 'transaction_id': transactionId})
          .eq('id', id);
    } catch (e) {
      debugPrint('PendingImportsRepository.markSupabaseCompleted: $e');
    }
  }

  // ---------------------------------------------------------------------------

  static PendingImportModel _toModel(PendingImport row) => PendingImportModel(
        id: row.id,
        userId: row.userId,
        localFilePath: row.localFilePath,
        mimeType: row.mimeType,
        status: row.status,
        createdAt: row.createdAt,
        sourceApp: row.sourceApp,
      );

  static Future<String> _copyToPendingDir(
    String sourcePath,
    String id,
    String mimeType,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final pendingDir = Directory(p.join(dir.path, 'pending_receipts'));
    if (!await pendingDir.exists()) {
      await pendingDir.create(recursive: true);
    }
    final ext = _extForMime(mimeType);
    final dest = File(p.join(pendingDir.path, '$id.$ext'));
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  static String _extForMime(String mimeType) {
    if (mimeType.contains('pdf')) return 'pdf';
    if (mimeType.contains('png')) return 'png';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
    return 'bin';
  }
}
