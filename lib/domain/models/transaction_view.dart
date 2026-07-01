import 'dart:typed_data';

import '../logic/impact_level.dart';

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
    this.thumbnailBytes,
    this.impactUser,
    this.ritualledAt,
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
  final String? localThumbnailPath;
  final Uint8List? thumbnailBytes;
  final String? impactUser;
  final DateTime? ritualledAt;

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
    DateTime? ritualledAt,
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
      impactUser: impactUser,
      ritualledAt: ritualledAt,
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
    DateTime? ritualledAt,
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
      localThumbnailPath: localThumbnailPath,
      thumbnailBytes: thumbnailBytes,
      impactUser: impactUser ?? this.impactUser,
      ritualledAt: ritualledAt ?? this.ritualledAt,
    );
  }
}
