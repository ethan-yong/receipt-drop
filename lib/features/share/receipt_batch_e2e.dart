import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import '../../data/repositories/ingest_receipt_request.dart';
import '../../data/repositories/transaction_repository_native.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_parse_pipeline.dart';

/// Result of running the headless save + local round-trip used by the batch CLI.
class ReceiptBatchE2eResult {
  const ReceiptBatchE2eResult({
    required this.transactionId,
    required this.persistedLineItemNames,
    required this.syncLineItemsPayload,
    required this.roundTripOk,
  });

  final String transactionId;
  final List<String> persistedLineItemNames;
  final List<Map<String, dynamic>> syncLineItemsPayload;
  final bool roundTripOk;

  Map<String, dynamic> toJson() => {
        'transactionId': transactionId,
        'persistedLineItemCount': persistedLineItemNames.length,
        'persistedLineItemNames': persistedLineItemNames,
        'syncLineItemsPayload': syncLineItemsPayload,
        'roundTripOk': roundTripOk,
      };
}

/// Builds the draft the app would show before save (line items included).
ReceiptIngestDraft draftFromParseResult({
  required ReceiptParseResult parsed,
  required String mimeType,
}) {
  return ReceiptIngestDraft(
    localFilePath: parsed.filePath,
    mimeType: mimeType,
    amountMyr: parsed.amountMyr,
    needsAmount: parsed.needsAmount,
    merchantRaw: parsed.merchantRaw,
    categoryGuess: parsed.categoryGuess,
    ocrConfidence: parsed.ocrConfidence,
    lineItems: parsed.lineItems,
  );
}

/// Auto-confirms amount and persists to an in-memory outbox, mirroring onSave.
///
/// Returns `null` when [parsed] still [ReceiptParseResult.needsAmount].
Future<ReceiptBatchE2eResult?> persistParsedReceiptE2e({
  required ReceiptParseResult parsed,
  required String mimeType,
  String userId = 'demo-user',
}) async {
  if (parsed.needsAmount || parsed.amountMyr == null) return null;

  final draft = draftFromParseResult(parsed: parsed, mimeType: mimeType);
  final request = draft.toIngestRequest(confirmedAmount: parsed.amountMyr!);

  final db = AppDatabase.memory();
  try {
    final repo = TransactionRepository(db);
    final saved = await repo.ingestReceipt(
      IngestReceiptRequest(
        localFilePath: request.localFilePath,
        mimeType: request.mimeType,
        amountMyr: request.amountMyr,
        needsAmount: request.needsAmount,
        merchantRaw: request.merchantRaw,
        categoryGuess: request.categoryGuess,
        ocrConfidence: request.ocrConfidence,
        userId: userId,
        lineItems: request.lineItems,
      ),
    );

    final fetched = await repo.getById(saved.id);
    final persistedNames =
        fetched?.lineItems?.map((it) => it.name).toList() ?? const [];
    final parsedNames = parsed.lineItems.map((it) => it.name).toList();

    final outboxItems = await (db.select(db.outboxLineItems)
          ..where((li) => li.transactionId.equals(saved.id))
          ..orderBy([(li) => OrderingTerm.asc(li.sortOrder)]))
        .get();

    final syncPayload = [
      for (final li in outboxItems)
        {
          'id': li.id,
          'user_id': userId,
          'transaction_id': saved.id,
          'name': li.name,
          'price_myr': li.priceMyr,
          'quantity': li.quantity,
          'confidence': li.confidence,
          'sort_order': li.sortOrder,
        },
    ];

    return ReceiptBatchE2eResult(
      transactionId: saved.id,
      persistedLineItemNames: persistedNames,
      syncLineItemsPayload: syncPayload,
      roundTripOk: _listsEqual(persistedNames, parsedNames),
    );
  } finally {
    await db.close();
  }
}

bool _listsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
