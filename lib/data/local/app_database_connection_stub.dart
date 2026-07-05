import 'package:drift/drift.dart';

LazyDatabase openAppDatabaseConnection() =>
    throw UnsupportedError(
      'openAppDatabaseConnection is only available on Flutter native. '
      'Use AppDatabase.memory() in CLI/test contexts.',
    );
