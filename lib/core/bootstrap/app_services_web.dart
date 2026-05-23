import '../../data/repositories/transaction_repository.dart';

/// Web: in-memory transactions (no dart:ffi / SQLite).
abstract final class AppServices {
  static late final TransactionRepository transactions;

  static Future<void> init() async {
    transactions = TransactionRepository();
    await transactions.seedDemoDataIfEmpty();
  }

  static Future<void> initForTest() async {
    transactions = TransactionRepository();
    await transactions.seedDemoDataIfEmpty();
  }

  static Future<void> dispose() async {
    await transactions.dispose();
  }
}
