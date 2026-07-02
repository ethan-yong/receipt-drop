import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    OutboxTransactions,
    OutboxArtifacts,
    OutboxLineItems,
    CategoryConfigCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppDatabaseConnection());

  /// In-memory database for widget/unit tests (no path_provider).
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(outboxTransactions, outboxTransactions.impactUser);
          }
          if (from < 3) {
            await m.addColumn(outboxTransactions, outboxTransactions.ritualledAt);
          }
          if (from < 4) {
            await m.createTable(outboxLineItems);
          }
        },
        // sqlite disables FK enforcement by default; needed for cascade
        // deletes on outbox_artifacts/outbox_line_items to actually fire.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

LazyDatabase openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'receipt_drop.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
