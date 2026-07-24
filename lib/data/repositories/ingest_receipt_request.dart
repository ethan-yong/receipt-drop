import 'dart:typed_data';

import '../../domain/logic/merchant_extractor.dart';
import '../../domain/models/field_correction.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/receipt_understanding.dart';

/// Parameters for saving a confirmed receipt to the local outbox.
class IngestReceiptRequest {
  const IngestReceiptRequest({
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
    this.userId = 'demo-user',
    this.impactUser,
    this.lineItems = const [],
    this.rawOcrText,
    this.ocrServiceConfidence,
    this.lineItemsConfidence,
    this.parseFailureReason,
    this.needsReview = false,
    this.merchantCandidates = const [],
    this.ocrHeaderText,
    this.understanding,
    this.pickedPlaceName,
    this.pickedPlaceGooglePlaceId,
    this.pickedPlaceLat,
    this.pickedPlaceLng,
    this.pickedPlaceLocked = false,
    this.fieldCorrections = const [],
  });

  final String localFilePath;
  final String mimeType;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String categoryGuess;
  final double? categoryConfidence;
  final String? categoryUser;
  final Uint8List? thumbnailBytes;
  final double? shareLocationLat;
  final double? shareLocationLng;
  final DateTime? shareLocationCapturedAt;
  final double? ocrConfidence;
  final String userId;
  final String? impactUser;
  final List<ReceiptLineItem> lineItems;

  /// Raw OCR text — only set when the parse failed or was low-confidence.
  final String? rawOcrText;
  final double? ocrServiceConfidence;
  final double? lineItemsConfidence;
  final String? parseFailureReason;

  /// Routes the transaction into the human review queue
  /// (pipeline_status = 'needs_review') instead of the normal flow.
  final bool needsReview;

  /// Ranked merchant-name guesses, synced alongside [merchantRaw] so
  /// enrichment can try more than one Places text-search query.
  final List<MerchantCandidate> merchantCandidates;

  /// Extra OCR context (top-of-receipt lines) synced for enrichment.
  final String? ocrHeaderText;

  /// LLM receipt understanding produced synchronously alongside OCR (see
  /// `receipt_parse_pipeline.dart`), persisted to the outbox row and synced
  /// so `enrich-transaction` can skip its own LLM call.
  final ReceiptUnderstanding? understanding;

  /// Place selected by the user in the pre-save picker.
  final String? pickedPlaceName;
  final String? pickedPlaceGooglePlaceId;
  final double? pickedPlaceLat;
  final double? pickedPlaceLng;

  /// When true, the above place fields are written immediately and
  /// [placeStatus] is set to 'user_locked' so enrichment skips Places.
  final bool pickedPlaceLocked;

  /// Predicted-vs-confirmed diffs captured on the confirm sheet — persisted
  /// alongside the transaction and synced for the feedback-learning
  /// surfaces. See `docs/plans/2026-07-23-feedback-learning-system.md`.
  final List<FieldCorrection> fieldCorrections;
}
