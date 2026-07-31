import 'dart:typed_data';

import '../../data/repositories/ingest_receipt_request.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../domain/models/field_correction.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/receipt_understanding.dart';

/// Parsed receipt ready for the save sheet (before user confirms amount).
class ReceiptIngestDraft {
  const ReceiptIngestDraft({
    required this.localFilePath,
    required this.mimeType,
    required this.amountMyr,
    required this.needsAmount,
    required this.merchantRaw,
    required this.categoryGuess,
    this.categoryConfidence,
    this.categoryUser,
    this.thumbnailBytes,
    this.shareLocationLat,
    this.shareLocationLng,
    this.shareLocationCapturedAt,
    this.ocrConfidence,
    this.lineItems = const [],
    this.rawOcrText,
    this.ocrServiceConfidence,
    this.lineItemsConfidence,
    this.parseFailureReason,
    this.lowConfidence = false,
    this.merchantCandidates = const [],
    this.ocrHeaderText,
    this.understanding,
    this.pickedPlaceName,
    this.pickedPlaceGooglePlaceId,
    this.pickedPlaceLat,
    this.pickedPlaceLng,
    this.pickedPlaceLocked = false,
    this.amountAlternativeMyr,
    this.amountSuspicious = false,
    this.amountFieldLowConfidence = false,
    this.merchantAmbiguous = false,
    this.merchantConfidence,
    this.fieldCorrections = const [],
    this.notes,
  });

  final String localFilePath;
  final String mimeType;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String categoryGuess;
  final double? categoryConfidence;

  /// Category override set by the user in the save sheet (writes to
  /// `category_user`; original `categoryGuess` is preserved).
  final String? categoryUser;
  final Uint8List? thumbnailBytes;
  final double? shareLocationLat;
  final double? shareLocationLng;
  final DateTime? shareLocationCapturedAt;
  final double? ocrConfidence;
  final List<ReceiptLineItem> lineItems;

  /// Raw OCR text (capped length), carried whenever OCR produced any text —
  /// feeds the server-side LLM receipt-understanding step.
  final String? rawOcrText;
  final double? ocrServiceConfidence;
  final double? lineItemsConfidence;
  final String? parseFailureReason;

  /// Combined-confidence verdict from [ReceiptParseResult.lowConfidence];
  /// kept on the draft so the save sheet doesn't re-derive it from
  /// [ocrConfidence] alone.
  final bool lowConfidence;

  /// Ranked merchant-name guesses, carried through to enrichment.
  final List<MerchantCandidate> merchantCandidates;

  /// Extra OCR context (top-of-receipt lines), carried through to enrichment.
  final String? ocrHeaderText;

  /// LLM receipt understanding produced synchronously alongside OCR — see
  /// `receipt_parse_pipeline.dart`. Carried through to the outbox row
  /// (`llmUnderstandingJson`) so `SyncWorker` can upload it, letting
  /// `enrich-transaction` skip its own LLM call.
  final ReceiptUnderstanding? understanding;

  /// Place chosen by the user in the pre-save picker.
  final String? pickedPlaceName;
  final String? pickedPlaceGooglePlaceId;
  final double? pickedPlaceLat;
  final double? pickedPlaceLng;
  final bool pickedPlaceLocked;

  /// Runner-up amount (MYR) when the top pick is suspicious/ambiguous.
  final double? amountAlternativeMyr;

  /// True when the top amount pick is suspicious/ambiguous and warrants
  /// extra user attention on the confirm sheet.
  final bool amountSuspicious;

  /// Per-field: amount's underlying OCR confidence was low.
  final bool amountFieldLowConfidence;

  /// Top-2 merchant candidates are close — surface "not this?" affordance.
  final bool merchantAmbiguous;

  /// Top merchant candidate's extraction confidence.
  final double? merchantConfidence;

  /// Predicted-vs-confirmed diffs captured by [ReceiptConfirmSheet] just
  /// before it overwrites the originals — feeds the feedback-learning
  /// surfaces (merchant alias write-back, category preference, OCR misread
  /// patterns). Empty on the freshly-parsed draft; populated only on the
  /// edited draft returned from the confirm sheet's save flow.
  final List<FieldCorrection> fieldCorrections;

  /// Freeform note — most often carried in from `PendingImportModel.note`
  /// (attached via the post-share notification's inline reply) before this
  /// draft ever reaches the confirm sheet. Null on a freshly-OCR'd draft.
  final String? notes;

  ReceiptIngestDraft copyWith({
    double? amountMyr,
    bool? needsAmount,
    String? merchantRaw,
    String? categoryGuess,
    String? categoryUser,
    List<ReceiptLineItem>? lineItems,
    String? pickedPlaceName,
    String? pickedPlaceGooglePlaceId,
    double? pickedPlaceLat,
    double? pickedPlaceLng,
    bool? pickedPlaceLocked,
    double? amountAlternativeMyr,
    bool? amountSuspicious,
    bool? amountFieldLowConfidence,
    bool? merchantAmbiguous,
    double? merchantConfidence,
    List<FieldCorrection>? fieldCorrections,
    String? notes,
  }) {
    return ReceiptIngestDraft(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: amountMyr ?? this.amountMyr,
      needsAmount: needsAmount ?? this.needsAmount,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      categoryGuess: categoryGuess ?? this.categoryGuess,
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser ?? this.categoryUser,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      lineItems: lineItems ?? this.lineItems,
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
      lowConfidence: lowConfidence,
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      understanding: understanding,
      pickedPlaceName: pickedPlaceName ?? this.pickedPlaceName,
      pickedPlaceGooglePlaceId:
          pickedPlaceGooglePlaceId ?? this.pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat ?? this.pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng ?? this.pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked ?? this.pickedPlaceLocked,
      amountAlternativeMyr: amountAlternativeMyr ?? this.amountAlternativeMyr,
      amountSuspicious: amountSuspicious ?? this.amountSuspicious,
      amountFieldLowConfidence:
          amountFieldLowConfidence ?? this.amountFieldLowConfidence,
      merchantAmbiguous: merchantAmbiguous ?? this.merchantAmbiguous,
      merchantConfidence: merchantConfidence ?? this.merchantConfidence,
      fieldCorrections: fieldCorrections ?? this.fieldCorrections,
      notes: notes ?? this.notes,
    );
  }

  /// Mirrors [ReceiptCaptureFlow] save: confirmed amount, line items carried through.
  IngestReceiptRequest toIngestRequest({
    required double confirmedAmount,
    String? impactUser,
  }) {
    return IngestReceiptRequest(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: confirmedAmount,
      needsAmount: false,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      impactUser: impactUser,
      lineItems: lineItems,
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      understanding: understanding,
      pickedPlaceName: pickedPlaceName,
      pickedPlaceGooglePlaceId: pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked,
      fieldCorrections: fieldCorrections,
      notes: notes,
    );
  }

  /// Saves without a confirmed amount: routes into the review queue instead
  /// of silently dropping the receipt. Parsed values (if any) are kept so the
  /// review screen can prefill them.
  IngestReceiptRequest toNeedsReviewRequest({String? impactUser}) {
    return IngestReceiptRequest(
      localFilePath: localFilePath,
      mimeType: mimeType,
      amountMyr: amountMyr,
      needsAmount: needsAmount,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      categoryConfidence: categoryConfidence,
      categoryUser: categoryUser,
      thumbnailBytes: thumbnailBytes,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
      shareLocationCapturedAt: shareLocationCapturedAt,
      ocrConfidence: ocrConfidence,
      impactUser: impactUser,
      lineItems: lineItems,
      rawOcrText: rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence,
      parseFailureReason: parseFailureReason,
      needsReview: true,
      merchantCandidates: merchantCandidates,
      ocrHeaderText: ocrHeaderText,
      understanding: understanding,
      pickedPlaceName: pickedPlaceName,
      pickedPlaceGooglePlaceId: pickedPlaceGooglePlaceId,
      pickedPlaceLat: pickedPlaceLat,
      pickedPlaceLng: pickedPlaceLng,
      pickedPlaceLocked: pickedPlaceLocked,
      fieldCorrections: fieldCorrections,
      notes: notes,
    );
  }
}
