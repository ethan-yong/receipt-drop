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

  String get effectiveCategory {
    final user = categoryUser?.trim();
    if (user != null && user.isNotEmpty) return user;
    final guess = categoryGuess?.trim();
    if (guess != null && guess.isNotEmpty) return guess;
    return 'Unclassified';
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
    );
  }
}
