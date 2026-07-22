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
    PendingImports,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openAppDatabaseConnection());

  /// In-memory database for widget/unit tests (no path_provider).
  AppDatabase.memory() : super(NativeDatabase.memory());

  /// File-backed database for tests that need to close and reopen the same
  /// file (e.g. exercising migration retries after a partial upgrade).
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 9;

  /// True when [column] already exists on [table] (SQLite `PRAGMA table_info`).
  ///
  /// Used so `ADD COLUMN` migrations stay idempotent: SQLite applies DDL even
  /// when a later step fails before Drift bumps `user_version`, so a retry
  /// would otherwise hit "duplicate column name".
  Future<bool> _hasColumn(TableInfo table, GeneratedColumn column) async {
    return _hasColumnNamed(table, column.name);
  }

  Future<bool> _hasColumnNamed(TableInfo table, String columnName) async {
    final rows = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  Future<void> _addColumnIfAbsent(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    if (!await _hasColumn(table, column)) {
      await m.addColumn(table, column);
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.impactUser);
          }
          if (from < 3) {
            if (!await _hasColumnNamed(outboxTransactions, 'ritualled_at')) {
              await customStatement(
                'ALTER TABLE ${outboxTransactions.actualTableName} '
                'ADD COLUMN ritualled_at INTEGER',
              );
            }
          }
          if (from < 4) {
            await m.createTable(outboxLineItems);
          }
          if (from < 5) {
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.rawOcrText);
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.ocrServiceConfidence);
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.lineItemsConfidence);
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.parseFailureReason);
          }
          if (from < 6) {
            await _addColumnIfAbsent(m, outboxTransactions,
                outboxTransactions.merchantCandidatesJson);
            await _addColumnIfAbsent(
                m, outboxTransactions, outboxTransactions.ocrHeaderText);
          }
          if (from < 7) {
            await _addColumnIfAbsent(m, outboxTransactions,
                outboxTransactions.llmUnderstandingJson);
          }
          if (from < 8) {
            await m.createTable(pendingImports);
          }
          if (from < 9) {
            if (await _hasColumnNamed(outboxTransactions, 'ritualled_at')) {
              await customStatement(
                'ALTER TABLE ${outboxTransactions.actualTableName} DROP COLUMN ritualled_at',
              );
            }
          }
        },
        // sqlite disables FK enforcement by default; needed for cascade
        // deletes on outbox_artifacts/outbox_line_items to actually fire.
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

