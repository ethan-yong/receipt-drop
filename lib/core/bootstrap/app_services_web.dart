import '../../data/repositories/transaction_repository_web.dart';

/// Web: in-memory transactions (no dart:ffi / SQLite).
abstract final class AppServices {
  static TransactionRepository? _transactions;

  static TransactionRepository get transactions {
    final repo = _transactions;
    if (repo == null) {
      throw StateError('AppServices.transactions accessed before init');
    }
    return repo;
  }

  static Future<void> init() async {
    _transactions = TransactionRepository();
    await _transactions!.seedDemoDataIfEmpty();
  }

  static Future<void> initForTest() async {
    await dispose();
    _transactions = TransactionRepository();
    await _transactions!.seedDemoDataIfEmpty();
  }

  static Future<void> dispose() async {
    await _transactions?.dispose();
    _transactions = null;
  }
}
