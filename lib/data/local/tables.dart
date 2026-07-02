import 'package:drift/drift.dart';

/// Local outbox mirror of [public.transactions] plus sync metadata.
@DataClassName('OutboxTransaction')
class OutboxTransactions extends Table {
  @override
  String get tableName => 'outbox_transactions';

  TextColumn get id => text()();

  TextColumn get userId => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get occurredAt =>
      dateTime().withDefault(currentDateAndTime)();

  RealColumn get amountMyr => real().nullable()();

  TextColumn get amountSource => text().nullable()();

  BoolColumn get needsAmount =>
      boolean().withDefault(const Constant(false))();

  TextColumn get merchantRaw => text().nullable()();

  TextColumn get merchantNormalized => text().nullable()();

  TextColumn get categoryGuess => text().nullable()();

  TextColumn get categoryUser => text().nullable()();

  RealColumn get categoryConfidence => real().nullable()();

  /// User override for the derived impact level ('low'|'med'|'high'); null
  /// means the level shown in [TransactionView.effectiveImpactLevel] is
  /// re-derived from [amountMyr] rather than stored here.
  TextColumn get impactUser => text().nullable()();

  TextColumn get placeStatus =>
      text().withDefault(const Constant('none'))();

  TextColumn get placeGooglePlaceId => text().nullable()();

  TextColumn get placeName => text().nullable()();

  RealColumn get placeLat => real().nullable()();

  RealColumn get placeLng => real().nullable()();

  RealColumn get placeConfidence => real().nullable()();

  RealColumn get shareLocationLat => real().nullable()();

  RealColumn get shareLocationLng => real().nullable()();

  DateTimeColumn get shareLocationCapturedAt => dateTime().nullable()();

  RealColumn get ocrConfidence => real().nullable()();

  TextColumn get pipelineStatus =>
      text().withDefault(const Constant('provisional'))();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  TextColumn get lastError => text().nullable()();

  IntColumn get retryCount =>
      integer().withDefault(const Constant(0))();

  /// Set after the receipt has been shown in the ritual animation.
  DateTimeColumn get ritualledAt => dateTime().nullable()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DataClassName('OutboxArtifact')
class OutboxArtifacts extends Table {
  @override
  String get tableName => 'outbox_artifacts';

  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get transactionId => text().references(
        OutboxTransactions,
        #id,
        onDelete: KeyAction.cascade,
      )();

  TextColumn get storagePath => text().nullable()();

  TextColumn get mimeType => text()();

  TextColumn get localFilePath => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DataClassName('OutboxLineItem')
class OutboxLineItems extends Table {
  @override
  String get tableName => 'outbox_line_items';

  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get transactionId => text().references(
        OutboxTransactions,
        #id,
        onDelete: KeyAction.cascade,
      )();

  TextColumn get name => text()();

  RealColumn get priceMyr => real()();

  IntColumn get quantity => integer().nullable()();

  RealColumn get confidence => real().nullable()();

  /// 0-based position in the parsed item list; SQLite doesn't guarantee row
  /// order, so this preserves the original OCR order on read.
  IntColumn get sortOrder => integer()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DataClassName('CategoryConfigCacheRow')
class CategoryConfigCache extends Table {
  @override
  String get tableName => 'category_config_cache';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get version => text().nullable()();

  TextColumn get etag => text().nullable()();

  TextColumn get jsonBody => text().nullable()();

  DateTimeColumn get updatedAt => dateTime().nullable()();
}
