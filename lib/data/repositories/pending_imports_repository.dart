import 'dart:async';
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

  /// Returns a single row to `local` only if it is still `processing`.
  ///
  /// Used when [PendingImportService.processImport] exits without a save —
  /// e.g. system-back / barrier dismiss of the confirm sheet, which skips
  /// the Cancel callback. Does not clobber `failed`.
  Future<void> resetToLocalIfProcessing(String id) async {
    await (_db.update(_db.pendingImports)
          ..where((t) => t.id.equals(id) & t.status.equals('processing')))
        .write(const PendingImportsCompanion(status: Value('local')));
  }

  /// Heals every row left in `processing`. That status is only valid while
  /// an in-flight [PendingImportService.processImport] owns the UI; after a
  /// process kill or a dismiss that skipped Cancel, cards would otherwise
  /// stay spinner-locked forever. Returns the number of rows cleared.
  ///
  /// Snapshots ids first so a Process tap that lands mid-heal cannot have
  /// its freshly-marked `processing` row wiped by a blanket status update.
  Future<int> resetAbandonedProcessing() async {
    final stuck = await (_db.select(_db.pendingImports)
          ..where((t) => t.status.equals('processing')))
        .get();
    if (stuck.isEmpty) return 0;
    final ids = stuck.map((r) => r.id).toList();
    return (_db.update(_db.pendingImports)
          ..where((t) => t.id.isIn(ids) & t.status.equals('processing')))
        .write(const PendingImportsCompanion(status: Value('local')));
  }

  /// Attaches a freeform note to a pending import — the write path used by
  /// the post-share notification's inline reply (both the foreground
  /// handler and the Android background-isolate callback) as well as any
  /// later in-app edit. A blank/whitespace-only [note] is a no-op: it must
  /// never overwrite an existing note with nothing. Returns `false` when the
  /// row no longer exists (e.g. already confirmed and deleted) so callers
  /// can treat a stale notification action as a safe no-op.
  Future<bool> setNote(String id, String note) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return false;
    final row = await (_db.select(_db.pendingImports)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return false;

    await (_db.update(_db.pendingImports)..where((t) => t.id.equals(id)))
        .write(PendingImportsCompanion(note: Value(trimmed)));

    unawaited(_syncNoteToSupabase(id, trimmed));
    return true;
  }

  /// Best-effort — the local write above is the source of truth; this just
  /// keeps the cloud mirror (`pending_receipts`, used mainly for the
  /// `sourceApp`/audit trail today) from going stale.
  Future<void> _syncNoteToSupabase(String id, String note) async {
    if (!Env.hasSupabaseConfig) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      await Supabase.instance.client
          .from('pending_receipts')
          .update({'note': note})
          .eq('id', id);
    } catch (e) {
      debugPrint('PendingImportsRepository.syncNoteToSupabase: $e');
    }
  }

  /// Attaches a best-effort resolved nearby-venue name — see
  /// `docs/plans/2026-07-30-pending-receipt-location-context.md`. Same
  /// blank-is-a-no-op and missing-row-is-a-safe-no-op contract as [setNote]
  /// (the row may already have been deleted if the receipt was confirmed
  /// before location resolution finished).
  Future<bool> setVenueLabel(String id, String label) async {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return false;
    final row = await (_db.select(_db.pendingImports)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return false;

    await (_db.update(_db.pendingImports)..where((t) => t.id.equals(id)))
        .write(PendingImportsCompanion(venueLabel: Value(trimmed)));

    unawaited(_syncVenueLabelToSupabase(id, trimmed));
    return true;
  }

  Future<void> _syncVenueLabelToSupabase(String id, String label) async {
    if (!Env.hasSupabaseConfig) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      await Supabase.instance.client
          .from('pending_receipts')
          .update({'venue_label': label})
          .eq('id', id);
    } catch (e) {
      debugPrint('PendingImportsRepository.syncVenueLabelToSupabase: $e');
    }
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
        note: row.note,
        venueLabel: row.venueLabel,
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
