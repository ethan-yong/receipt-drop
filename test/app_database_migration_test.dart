import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/local/app_database.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('receipt_drop_migration');
    dbFile = File('${tempDir.path}/app.db');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  Future<AppDatabase> openDb() async {
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    // Any query forces the database open, which runs pending migrations.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('reopening after a partial v7 migration does not crash', () async {
    // Simulate the crash state: the schema is fully at v7 (the
    // llm_understanding_json column exists) but user_version is still 6
    // because a previous run died before drift bumped it. Reopening must
    // re-run the v7 step without hitting "duplicate column name", then
    // continue to apply the v8 step.
    var db = await openDb();
    await db.customStatement('PRAGMA user_version = 6');
    await db.close();

    db = await openDb();
    expect(await userVersion(db), 9);
    await db.customSelect(
      'SELECT llm_understanding_json FROM outbox_transactions',
    ).get();
    await db.close();
  });

  test('re-running every upgrade step against a v1 schema reaches current version',
      () async {
    var db = await openDb();
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = await openDb();
    expect(await userVersion(db), 9);
    await db.close();
  });

  test('reopening after a partial v8 migration does not crash', () async {
    // Simulate the crash state: the pending_imports table already exists but
    // user_version is still 7. Drift's createTable uses IF NOT EXISTS so
    // re-running must not throw "table already exists".
    var db = await openDb();
    await db.customStatement('PRAGMA user_version = 7');
    await db.close();

    db = await openDb();
    expect(await userVersion(db), 9);
    await db.customSelect('SELECT id FROM pending_imports').get();
    await db.close();
  });
}
