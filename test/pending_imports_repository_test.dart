import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/data/local/app_database.dart';
import 'package:receipt_drop/data/repositories/pending_imports_repository.dart';

void main() {
  test(
    'resetAbandonedProcessing returns stuck processing rows to local',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = PendingImportsRepository(db);

      await db.into(db.pendingImports).insert(
            PendingImportsCompanion.insert(
              id: 'stuck',
              userId: 'u1',
              localFilePath: '/tmp/stuck.jpg',
              mimeType: 'image/jpeg',
              status: const Value('processing'),
            ),
          );
      await db.into(db.pendingImports).insert(
            PendingImportsCompanion.insert(
              id: 'ok-local',
              userId: 'u1',
              localFilePath: '/tmp/ok.jpg',
              mimeType: 'image/jpeg',
              status: const Value('local'),
            ),
          );
      await db.into(db.pendingImports).insert(
            PendingImportsCompanion.insert(
              id: 'failed',
              userId: 'u1',
              localFilePath: '/tmp/failed.jpg',
              mimeType: 'image/jpeg',
              status: const Value('failed'),
            ),
          );

      final cleared = await repo.resetAbandonedProcessing();
      expect(cleared, 1);

      final rows = await db.select(db.pendingImports).get();
      final byId = {for (final r in rows) r.id: r.status};
      expect(byId['stuck'], 'local');
      expect(byId['ok-local'], 'local');
      expect(byId['failed'], 'failed');
    },
  );

  test(
    'resetToLocalIfProcessing only rewrites rows still marked processing',
    () async {
      final db = AppDatabase.memory();
      addTearDown(db.close);
      final repo = PendingImportsRepository(db);

      await db.into(db.pendingImports).insert(
            PendingImportsCompanion.insert(
              id: 'proc',
              userId: 'u1',
              localFilePath: '/tmp/a.jpg',
              mimeType: 'image/jpeg',
              status: const Value('processing'),
            ),
          );
      await db.into(db.pendingImports).insert(
            PendingImportsCompanion.insert(
              id: 'failed',
              userId: 'u1',
              localFilePath: '/tmp/b.jpg',
              mimeType: 'image/jpeg',
              status: const Value('failed'),
            ),
          );

      await repo.resetToLocalIfProcessing('proc');
      await repo.resetToLocalIfProcessing('failed');

      final rows = await db.select(db.pendingImports).get();
      final byId = {for (final r in rows) r.id: r.status};
      expect(byId['proc'], 'local');
      expect(byId['failed'], 'failed');
    },
  );
}
