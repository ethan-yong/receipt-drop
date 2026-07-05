import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'app_database_connection_stub.dart'
    if (dart.library.ui) 'app_database_connection_flutter.dart';
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
  int get schemaVersion => 5;

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
          if (from < 5) {
            await m.addColumn(outboxTransactions, outboxTransactions.rawOcrText);
            await m.addColumn(
                outboxTransactions, outboxTransactions.ocrServiceConfidence);
            await m.addColumn(
                outboxTransactions, outboxTransactions.lineItemsConfidence);
            await m.addColumn(
                outboxTransactions, outboxTransactions.parseFailureReason);
          }
        },
        // sqlite disables FK enforcement by default; needed for cascade
        // deletes on outbox_artifacts/outbox_line_items to actually fire.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

