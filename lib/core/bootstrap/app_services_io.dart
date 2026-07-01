import 'package:flutter/foundation.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/transaction_repository_native.dart';

/// Native/mobile/desktop: Drift SQLite outbox.
abstract final class AppServices {
  static AppDatabase? _database;
  static TransactionRepository? _transactions;

  static AppDatabase get database {
    final db = _database;
    if (db == null) {
      throw StateError('AppServices.database accessed before init');
    }
    return db;
  }

  static TransactionRepository get transactions {
    final repo = _transactions;
    if (repo == null) {
      throw StateError('AppServices.transactions accessed before init');
    }
    return repo;
  }

  static Future<void> init() async {
    _database = AppDatabase();
    _transactions = TransactionRepository(_database!);
    await _transactions!.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await _transactions!.seedReceiptShowcaseIfEmpty();
    }
  }

  static Future<void> initForTest() async {
    await dispose();
    _database = AppDatabase.memory();
    _transactions = TransactionRepository(_database!);
    await _transactions!.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await _transactions!.seedReceiptShowcaseIfEmpty();
    }
  }

  static Future<void> dispose() async {
    await _database?.close();
    _database = null;
    _transactions = null;
  }
}
