import 'dart:typed_data';

import '../logic/impact_level.dart';
import 'receipt_line_item.dart';

/// Unified transaction row for UI (outbox-first; cloud merge later).
class TransactionView {
  const TransactionView({
    required this.id,
    required this.occurredAt,
    required this.amountMyr,
    required this.needsAmount,
    required this.merchantRaw,
    required this.categoryGuess,
    required this.categoryUser,
    required this.placeName,
    required this.placeGooglePlaceId,
    required this.placeLat,
    required this.placeLng,
    required this.syncStatus,
    required this.pipelineStatus,
    required this.localThumbnailPath,
    this.remoteStoragePath,
    this.thumbnailBytes,
    this.impactUser,
    this.lineItems,
    this.rawOcrText,
    this.ocrConfidence,
    this.shareLocationLat,
    this.shareLocationLng,
  });

  final String id;
  final DateTime occurredAt;
  final double? amountMyr;
  final bool needsAmount;
  final String? merchantRaw;
  final String? categoryGuess;
  final String? categoryUser;
  final String? placeName;
  final String? placeGooglePlaceId;
  final double? placeLat;
  final double? placeLng;
  final String syncStatus;
  final String pipelineStatus;

  /// On-device path from [OutboxArtifacts.localFilePath], when present.
  final String? localThumbnailPath;

  /// Remote path in the private `receipts` Storage bucket
  /// ([OutboxArtifacts.storagePath]), used to mint a signed URL when the
  /// local file is gone (reinstall / new device).
  final String? remoteStoragePath;
  final Uint8List? thumbnailBytes;
  final String? impactUser;
  final List<ReceiptLineItem>? lineItems;

  /// Raw OCR text kept as evidence on failed/low-confidence parses; shown on
  /// the review screen so the user can find the amount themselves.
  final String? rawOcrText;

  /// Amount-extraction confidence (0..1) as stored on the outbox row.
  final double? ocrConfidence;

  final double? shareLocationLat;
  final double? shareLocationLng;

  /// Waiting for one-tap human confirmation on the review screen.
  bool get needsReview => pipelineStatus == 'needs_review';

  String get effectiveCategory {
    final user = categoryUser?.trim();
    if (user != null && user.isNotEmpty) return user;
    final guess = categoryGuess?.trim();
    if (guess != null && guess.isNotEmpty) return guess;
    return 'Unclassified';
  }

  /// User override wins; otherwise re-derived from [amountMyr] (there is no
  /// stored "guess" for impact — it's cheap to recompute, unlike category).
  ImpactLevel get effectiveImpactLevel {
    switch (impactUser) {
      case 'low':
        return ImpactLevel.low;
      case 'med':
        return ImpactLevel.med;
      case 'high':
        return ImpactLevel.high;
      default:
        return deriveImpactLevel(amountMyr);
    }
  }

  String get displayPlace {
    final name = placeName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final merchant = merchantRaw?.trim();
    if (merchant != null && merchant.isNotEmpty) return merchant;
    return 'No place';
  }

  bool get isPendingSync =>
      syncStatus == 'pending' || syncStatus == 'syncing';

  bool get isStuckSync => syncStatus == 'stuck';

  bool get includeInCharts {
    if (pipelineStatus == 'failed_enrichment' && amountMyr == null) {
      return false;
    }
    return amountMyr != null;
  }

  factory TransactionView.fromOutbox({
    required String id,
    required DateTime occurredAt,
    required double? amountMyr,
    required bool needsAmount,
    required String? merchantRaw,
    required String? categoryGuess,
    required String? categoryUser,
    required String? placeName,
    required String? placeGooglePlaceId,
    required double? placeLat,
    required double? placeLng,
    required String syncStatus,
    required String pipelineStatus,
    String? impactUser,
    List<ReceiptLineItem>? lineItems,
    double? shareLocationLat,
    double? shareLocationLng,
  }) {
    return TransactionView(
      id: id,
      occurredAt: occurredAt,
      amountMyr: amountMyr,
      needsAmount: needsAmount,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      categoryUser: categoryUser,
      placeName: placeName,
      placeGooglePlaceId: placeGooglePlaceId,
      placeLat: placeLat,
      placeLng: placeLng,
      syncStatus: syncStatus,
      pipelineStatus: pipelineStatus,
      localThumbnailPath: null,
      remoteStoragePath: null,
      impactUser: impactUser,
      lineItems: lineItems,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
    );
  }

  TransactionView copyWith({
    double? amountMyr,
    bool? needsAmount,
    String? categoryUser,
    String? placeName,
    String? placeGooglePlaceId,
    double? placeLat,
    double? placeLng,
    DateTime? occurredAt,
    String? impactUser,
    List<ReceiptLineItem>? lineItems,
    String? localThumbnailPath,
    String? remoteStoragePath,
  }) {
    return TransactionView(
      id: id,
      occurredAt: occurredAt ?? this.occurredAt,
      amountMyr: amountMyr ?? this.amountMyr,
      needsAmount: needsAmount ?? this.needsAmount,
      merchantRaw: merchantRaw,
      categoryGuess: categoryGuess,
      categoryUser: categoryUser ?? this.categoryUser,
      placeName: placeName ?? this.placeName,
      placeGooglePlaceId:
          placeGooglePlaceId ?? this.placeGooglePlaceId,
      placeLat: placeLat ?? this.placeLat,
      placeLng: placeLng ?? this.placeLng,
      syncStatus: syncStatus,
      pipelineStatus: pipelineStatus,
      localThumbnailPath: localThumbnailPath ?? this.localThumbnailPath,
      remoteStoragePath: remoteStoragePath ?? this.remoteStoragePath,
      thumbnailBytes: thumbnailBytes,
      impactUser: impactUser ?? this.impactUser,
      lineItems: lineItems ?? this.lineItems,
      rawOcrText: rawOcrText,
      ocrConfidence: ocrConfidence,
      shareLocationLat: shareLocationLat,
      shareLocationLng: shareLocationLng,
    );
  }
}
