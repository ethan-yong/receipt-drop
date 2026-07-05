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
    required this.pipelineStatus,
    required this.needsReview,
  });

  final String transactionId;
  final List<String> persistedLineItemNames;
  final List<Map<String, dynamic>> syncLineItemsPayload;
  final bool roundTripOk;
  final String pipelineStatus;
  final bool needsReview;

  Map<String, dynamic> toJson() => {
        'transactionId': transactionId,
        'persistedLineItemCount': persistedLineItemNames.length,
        'persistedLineItemNames': persistedLineItemNames,
        'syncLineItemsPayload': syncLineItemsPayload,
        'roundTripOk': roundTripOk,
        'pipelineStatus': pipelineStatus,
        'needsReview': needsReview,
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
    rawOcrText: (parsed.needsAmount || parsed.lowConfidence) &&
            parsed.ocrText.isNotEmpty
        ? parsed.ocrText
        : null,
    ocrServiceConfidence: parsed.ocrServiceConfidence,
    lineItemsConfidence: parsed.lineItemsConfidence,
    parseFailureReason: parsed.parseFailureReason,
    lowConfidence: parsed.lowConfidence,
  );
}

/// Persists to an in-memory outbox, mirroring onSave. Never drops a receipt:
/// parses without an amount or with low confidence are saved into the review
/// queue (pipeline_status = 'needs_review') instead of being skipped.
Future<ReceiptBatchE2eResult> persistParsedReceiptE2e({
  required ReceiptParseResult parsed,
  required String mimeType,
  String userId = 'demo-user',
}) async {
  final draft = draftFromParseResult(parsed: parsed, mimeType: mimeType);
  final needsReview = parsed.needsAmount ||
      parsed.amountMyr == null ||
      parsed.lowConfidence;
  final request = needsReview
      ? draft.toNeedsReviewRequest()
      : draft.toIngestRequest(confirmedAmount: parsed.amountMyr!);

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
        rawOcrText: request.rawOcrText,
        ocrServiceConfidence: request.ocrServiceConfidence,
        lineItemsConfidence: request.lineItemsConfidence,
        parseFailureReason: request.parseFailureReason,
        needsReview: request.needsReview,
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
      pipelineStatus: fetched?.pipelineStatus ?? saved.pipelineStatus,
      needsReview: fetched?.needsReview ?? saved.needsReview,
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
