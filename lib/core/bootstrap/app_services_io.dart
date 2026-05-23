import '../../data/local/app_database.dart';
import '../../data/repositories/transaction_repository.dart';

/// Native/mobile/desktop: Drift SQLite outbox.
abstract final class AppServices {
  static late final AppDatabase database;
  static late final TransactionRepository transactions;

  static Future<void> init() async {
    database = AppDatabase();
    transactions = TransactionRepository(database);
    await transactions.seedDemoDataIfEmpty();
  }

  static Future<void> initForTest() async {
    database = AppDatabase.memory();
    transactions = TransactionRepository(database);
    await transactions.seedDemoDataIfEmpty();
  }

  static Future<void> dispose() async {
    await database.close();
  }
}
