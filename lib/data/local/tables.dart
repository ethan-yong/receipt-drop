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

  /// Raw OCR text — always populated (client caps it ~8000 chars) since the
  /// LLM receipt-understanding step, not only for failed/low-confidence
  /// parses; still doubles as labeled data for fixing parser rules later.
  TextColumn get rawOcrText => text().nullable()();

  /// OCR engine's scan-quality confidence (mean word confidence, 0..1).
  /// Distinct from [ocrConfidence], which scores the amount *extraction*.
  RealColumn get ocrServiceConfidence => real().nullable()();

  /// Aggregate confidence over extracted line items.
  RealColumn get lineItemsConfidence => real().nullable()();

  /// Machine-readable reason when amount parsing failed outright.
  TextColumn get parseFailureReason => text().nullable()();

  TextColumn get pipelineStatus =>
      text().withDefault(const Constant('provisional'))();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('pending'))();

  TextColumn get lastError => text().nullable()();

  IntColumn get retryCount =>
      integer().withDefault(const Constant(0))();

  /// Ranked merchant-name candidates (JSON-encoded `MerchantCandidate` list),
  /// synced to `transactions.merchant_candidates` (jsonb) so enrichment can
  /// try more than one Places text-search query.
  TextColumn get merchantCandidatesJson => text().nullable()();

  /// Top-of-receipt OCR lines, always populated (unlike [rawOcrText], which
  /// is review-only) — extra context for merchant/place enrichment.
  TextColumn get ocrHeaderText => text().nullable()();

  /// LLM receipt-understanding step's structured output (JSON-encoded
  /// `ReceiptUnderstanding`), produced synchronously alongside OCR at
  /// capture time and synced to `transactions.llm_understanding` (jsonb) so
  /// `enrich-transaction` can skip calling the LLM itself.
  TextColumn get llmUnderstandingJson => text().nullable()();

  /// LLM OCR-cleanup step's corrected transcript (opt-in server-side via
  /// `LLM_CLEANUP_ENABLED`), synced to `transactions.cleaned_ocr_text` —
  /// additive alongside (never replacing) [rawOcrText]. Null when cleanup
  /// wasn't attempted or produced nothing the server's per-line
  /// edit-distance guard accepted.
  TextColumn get cleanedOcrText => text().nullable()();

  /// Per-line corrections the cleanup guard accepted (JSON-encoded list of
  /// `{line_index, original, corrected}`), synced to
  /// `transactions.ocr_corrections` (jsonb).
  TextColumn get ocrCorrectionsJson => text().nullable()();

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

@DataClassName('PendingImport')
class PendingImports extends Table {
  @override
  String get tableName => 'pending_imports';

  TextColumn get id => text()();

  TextColumn get userId => text()();

  TextColumn get localFilePath => text()();

  TextColumn get mimeType => text()();

  TextColumn get sourceApp => text().nullable()();

  /// 'local' | 'processing' | 'failed'
  TextColumn get status => text().withDefault(const Constant('local'))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

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
