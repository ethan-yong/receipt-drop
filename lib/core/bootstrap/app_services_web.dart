import 'package:flutter/foundation.dart';

import '../../data/repositories/insights_repository_web.dart';
import '../../data/repositories/transaction_repository_web.dart';
import '../../domain/models/pending_import_model.dart';

/// No-op pending imports stub for web (share intents are not supported on web).
class _PendingImportsStub {
  Stream<List<PendingImportModel>> watchAll() => const Stream.empty();

  Future<PendingImportModel> create({
    required String userId,
    required String sourcePath,
    required String mimeType,
    String? sourceApp,
  }) async =>
      throw UnsupportedError('Pending imports not supported on web');

  Future<void> updateStatus(String id, String status) async {}
  Future<void> delete(String id) async {}
  Future<void> syncToSupabase(PendingImportModel import) async {}
  Future<void> markSupabaseCompleted(String id, String transactionId) async {}
}

/// Web: in-memory transactions (no dart:ffi / SQLite).
abstract final class AppServices {
  static TransactionRepository? _transactions;
  static final _pendingImportsStub = _PendingImportsStub();
  static final InsightsRepository _insights = InsightsRepository();

  static TransactionRepository get transactions {
    final repo = _transactions;
    if (repo == null) {
      throw StateError('AppServices.transactions accessed before init');
    }
    return repo;
  }

  static _PendingImportsStub get pendingImports => _pendingImportsStub;

  static InsightsRepository get insights => _insights;

  static Future<void> init() async {
    _transactions = TransactionRepository();
    await _transactions!.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await _transactions!.seedReceiptShowcaseIfEmpty();
    }
  }

  static Future<void> initForTest() async {
    await dispose();
    _transactions = TransactionRepository();
    await _transactions!.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await _transactions!.seedReceiptShowcaseIfEmpty();
    }
  }

  static Future<void> dispose() async {
    await _transactions?.dispose();
    _transactions = null;
  }
}
