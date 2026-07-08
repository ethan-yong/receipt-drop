// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $OutboxTransactionsTable extends OutboxTransactions
    with TableInfo<$OutboxTransactionsTable, OutboxTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _amountMyrMeta = const VerificationMeta(
    'amountMyr',
  );
  @override
  late final GeneratedColumn<double> amountMyr = GeneratedColumn<double>(
    'amount_myr',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountSourceMeta = const VerificationMeta(
    'amountSource',
  );
  @override
  late final GeneratedColumn<String> amountSource = GeneratedColumn<String>(
    'amount_source',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsAmountMeta = const VerificationMeta(
    'needsAmount',
  );
  @override
  late final GeneratedColumn<bool> needsAmount = GeneratedColumn<bool>(
    'needs_amount',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_amount" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _merchantRawMeta = const VerificationMeta(
    'merchantRaw',
  );
  @override
  late final GeneratedColumn<String> merchantRaw = GeneratedColumn<String>(
    'merchant_raw',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _merchantNormalizedMeta =
      const VerificationMeta('merchantNormalized');
  @override
  late final GeneratedColumn<String> merchantNormalized =
      GeneratedColumn<String>(
        'merchant_normalized',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _categoryGuessMeta = const VerificationMeta(
    'categoryGuess',
  );
  @override
  late final GeneratedColumn<String> categoryGuess = GeneratedColumn<String>(
    'category_guess',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryUserMeta = const VerificationMeta(
    'categoryUser',
  );
  @override
  late final GeneratedColumn<String> categoryUser = GeneratedColumn<String>(
    'category_user',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryConfidenceMeta =
      const VerificationMeta('categoryConfidence');
  @override
  late final GeneratedColumn<double> categoryConfidence =
      GeneratedColumn<double>(
        'category_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _impactUserMeta = const VerificationMeta(
    'impactUser',
  );
  @override
  late final GeneratedColumn<String> impactUser = GeneratedColumn<String>(
    'impact_user',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeStatusMeta = const VerificationMeta(
    'placeStatus',
  );
  @override
  late final GeneratedColumn<String> placeStatus = GeneratedColumn<String>(
    'place_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('none'),
  );
  static const VerificationMeta _placeGooglePlaceIdMeta =
      const VerificationMeta('placeGooglePlaceId');
  @override
  late final GeneratedColumn<String> placeGooglePlaceId =
      GeneratedColumn<String>(
        'place_google_place_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _placeNameMeta = const VerificationMeta(
    'placeName',
  );
  @override
  late final GeneratedColumn<String> placeName = GeneratedColumn<String>(
    'place_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeLatMeta = const VerificationMeta(
    'placeLat',
  );
  @override
  late final GeneratedColumn<double> placeLat = GeneratedColumn<double>(
    'place_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeLngMeta = const VerificationMeta(
    'placeLng',
  );
  @override
  late final GeneratedColumn<double> placeLng = GeneratedColumn<double>(
    'place_lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeConfidenceMeta = const VerificationMeta(
    'placeConfidence',
  );
  @override
  late final GeneratedColumn<double> placeConfidence = GeneratedColumn<double>(
    'place_confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareLocationLatMeta = const VerificationMeta(
    'shareLocationLat',
  );
  @override
  late final GeneratedColumn<double> shareLocationLat = GeneratedColumn<double>(
    'share_location_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareLocationLngMeta = const VerificationMeta(
    'shareLocationLng',
  );
  @override
  late final GeneratedColumn<double> shareLocationLng = GeneratedColumn<double>(
    'share_location_lng',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shareLocationCapturedAtMeta =
      const VerificationMeta('shareLocationCapturedAt');
  @override
  late final GeneratedColumn<DateTime> shareLocationCapturedAt =
      GeneratedColumn<DateTime>(
        'share_location_captured_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _ocrConfidenceMeta = const VerificationMeta(
    'ocrConfidence',
  );
  @override
  late final GeneratedColumn<double> ocrConfidence = GeneratedColumn<double>(
    'ocr_confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rawOcrTextMeta = const VerificationMeta(
    'rawOcrText',
  );
  @override
  late final GeneratedColumn<String> rawOcrText = GeneratedColumn<String>(
    'raw_ocr_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ocrServiceConfidenceMeta =
      const VerificationMeta('ocrServiceConfidence');
  @override
  late final GeneratedColumn<double> ocrServiceConfidence =
      GeneratedColumn<double>(
        'ocr_service_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lineItemsConfidenceMeta =
      const VerificationMeta('lineItemsConfidence');
  @override
  late final GeneratedColumn<double> lineItemsConfidence =
      GeneratedColumn<double>(
        'line_items_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _parseFailureReasonMeta =
      const VerificationMeta('parseFailureReason');
  @override
  late final GeneratedColumn<String> parseFailureReason =
      GeneratedColumn<String>(
        'parse_failure_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _pipelineStatusMeta = const VerificationMeta(
    'pipelineStatus',
  );
  @override
  late final GeneratedColumn<String> pipelineStatus = GeneratedColumn<String>(
    'pipeline_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('provisional'),
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _ritualledAtMeta = const VerificationMeta(
    'ritualledAt',
  );
  @override
  late final GeneratedColumn<DateTime> ritualledAt = GeneratedColumn<DateTime>(
    'ritualled_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _merchantCandidatesJsonMeta =
      const VerificationMeta('merchantCandidatesJson');
  @override
  late final GeneratedColumn<String> merchantCandidatesJson =
      GeneratedColumn<String>(
        'merchant_candidates_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _ocrHeaderTextMeta = const VerificationMeta(
    'ocrHeaderText',
  );
  @override
  late final GeneratedColumn<String> ocrHeaderText = GeneratedColumn<String>(
    'ocr_header_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    createdAt,
    occurredAt,
    amountMyr,
    amountSource,
    needsAmount,
    merchantRaw,
    merchantNormalized,
    categoryGuess,
    categoryUser,
    categoryConfidence,
    impactUser,
    placeStatus,
    placeGooglePlaceId,
    placeName,
    placeLat,
    placeLng,
    placeConfidence,
    shareLocationLat,
    shareLocationLng,
    shareLocationCapturedAt,
    ocrConfidence,
    rawOcrText,
    ocrServiceConfidence,
    lineItemsConfidence,
    parseFailureReason,
    pipelineStatus,
    syncStatus,
    lastError,
    retryCount,
    ritualledAt,
    merchantCandidatesJson,
    ocrHeaderText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxTransaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    }
    if (data.containsKey('amount_myr')) {
      context.handle(
        _amountMyrMeta,
        amountMyr.isAcceptableOrUnknown(data['amount_myr']!, _amountMyrMeta),
      );
    }
    if (data.containsKey('amount_source')) {
      context.handle(
        _amountSourceMeta,
        amountSource.isAcceptableOrUnknown(
          data['amount_source']!,
          _amountSourceMeta,
        ),
      );
    }
    if (data.containsKey('needs_amount')) {
      context.handle(
        _needsAmountMeta,
        needsAmount.isAcceptableOrUnknown(
          data['needs_amount']!,
          _needsAmountMeta,
        ),
      );
    }
    if (data.containsKey('merchant_raw')) {
      context.handle(
        _merchantRawMeta,
        merchantRaw.isAcceptableOrUnknown(
          data['merchant_raw']!,
          _merchantRawMeta,
        ),
      );
    }
    if (data.containsKey('merchant_normalized')) {
      context.handle(
        _merchantNormalizedMeta,
        merchantNormalized.isAcceptableOrUnknown(
          data['merchant_normalized']!,
          _merchantNormalizedMeta,
        ),
      );
    }
    if (data.containsKey('category_guess')) {
      context.handle(
        _categoryGuessMeta,
        categoryGuess.isAcceptableOrUnknown(
          data['category_guess']!,
          _categoryGuessMeta,
        ),
      );
    }
    if (data.containsKey('category_user')) {
      context.handle(
        _categoryUserMeta,
        categoryUser.isAcceptableOrUnknown(
          data['category_user']!,
          _categoryUserMeta,
        ),
      );
    }
    if (data.containsKey('category_confidence')) {
      context.handle(
        _categoryConfidenceMeta,
        categoryConfidence.isAcceptableOrUnknown(
          data['category_confidence']!,
          _categoryConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('impact_user')) {
      context.handle(
        _impactUserMeta,
        impactUser.isAcceptableOrUnknown(data['impact_user']!, _impactUserMeta),
      );
    }
    if (data.containsKey('place_status')) {
      context.handle(
        _placeStatusMeta,
        placeStatus.isAcceptableOrUnknown(
          data['place_status']!,
          _placeStatusMeta,
        ),
      );
    }
    if (data.containsKey('place_google_place_id')) {
      context.handle(
        _placeGooglePlaceIdMeta,
        placeGooglePlaceId.isAcceptableOrUnknown(
          data['place_google_place_id']!,
          _placeGooglePlaceIdMeta,
        ),
      );
    }
    if (data.containsKey('place_name')) {
      context.handle(
        _placeNameMeta,
        placeName.isAcceptableOrUnknown(data['place_name']!, _placeNameMeta),
      );
    }
    if (data.containsKey('place_lat')) {
      context.handle(
        _placeLatMeta,
        placeLat.isAcceptableOrUnknown(data['place_lat']!, _placeLatMeta),
      );
    }
    if (data.containsKey('place_lng')) {
      context.handle(
        _placeLngMeta,
        placeLng.isAcceptableOrUnknown(data['place_lng']!, _placeLngMeta),
      );
    }
    if (data.containsKey('place_confidence')) {
      context.handle(
        _placeConfidenceMeta,
        placeConfidence.isAcceptableOrUnknown(
          data['place_confidence']!,
          _placeConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('share_location_lat')) {
      context.handle(
        _shareLocationLatMeta,
        shareLocationLat.isAcceptableOrUnknown(
          data['share_location_lat']!,
          _shareLocationLatMeta,
        ),
      );
    }
    if (data.containsKey('share_location_lng')) {
      context.handle(
        _shareLocationLngMeta,
        shareLocationLng.isAcceptableOrUnknown(
          data['share_location_lng']!,
          _shareLocationLngMeta,
        ),
      );
    }
    if (data.containsKey('share_location_captured_at')) {
      context.handle(
        _shareLocationCapturedAtMeta,
        shareLocationCapturedAt.isAcceptableOrUnknown(
          data['share_location_captured_at']!,
          _shareLocationCapturedAtMeta,
        ),
      );
    }
    if (data.containsKey('ocr_confidence')) {
      context.handle(
        _ocrConfidenceMeta,
        ocrConfidence.isAcceptableOrUnknown(
          data['ocr_confidence']!,
          _ocrConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('raw_ocr_text')) {
      context.handle(
        _rawOcrTextMeta,
        rawOcrText.isAcceptableOrUnknown(
          data['raw_ocr_text']!,
          _rawOcrTextMeta,
        ),
      );
    }
    if (data.containsKey('ocr_service_confidence')) {
      context.handle(
        _ocrServiceConfidenceMeta,
        ocrServiceConfidence.isAcceptableOrUnknown(
          data['ocr_service_confidence']!,
          _ocrServiceConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('line_items_confidence')) {
      context.handle(
        _lineItemsConfidenceMeta,
        lineItemsConfidence.isAcceptableOrUnknown(
          data['line_items_confidence']!,
          _lineItemsConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('parse_failure_reason')) {
      context.handle(
        _parseFailureReasonMeta,
        parseFailureReason.isAcceptableOrUnknown(
          data['parse_failure_reason']!,
          _parseFailureReasonMeta,
        ),
      );
    }
    if (data.containsKey('pipeline_status')) {
      context.handle(
        _pipelineStatusMeta,
        pipelineStatus.isAcceptableOrUnknown(
          data['pipeline_status']!,
          _pipelineStatusMeta,
        ),
      );
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('ritualled_at')) {
      context.handle(
        _ritualledAtMeta,
        ritualledAt.isAcceptableOrUnknown(
          data['ritualled_at']!,
          _ritualledAtMeta,
        ),
      );
    }
    if (data.containsKey('merchant_candidates_json')) {
      context.handle(
        _merchantCandidatesJsonMeta,
        merchantCandidatesJson.isAcceptableOrUnknown(
          data['merchant_candidates_json']!,
          _merchantCandidatesJsonMeta,
        ),
      );
    }
    if (data.containsKey('ocr_header_text')) {
      context.handle(
        _ocrHeaderTextMeta,
        ocrHeaderText.isAcceptableOrUnknown(
          data['ocr_header_text']!,
          _ocrHeaderTextMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxTransaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      amountMyr: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount_myr'],
      ),
      amountSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}amount_source'],
      ),
      needsAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_amount'],
      )!,
      merchantRaw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merchant_raw'],
      ),
      merchantNormalized: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merchant_normalized'],
      ),
      categoryGuess: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_guess'],
      ),
      categoryUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_user'],
      ),
      categoryConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}category_confidence'],
      ),
      impactUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}impact_user'],
      ),
      placeStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_status'],
      )!,
      placeGooglePlaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_google_place_id'],
      ),
      placeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_name'],
      ),
      placeLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}place_lat'],
      ),
      placeLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}place_lng'],
      ),
      placeConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}place_confidence'],
      ),
      shareLocationLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}share_location_lat'],
      ),
      shareLocationLng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}share_location_lng'],
      ),
      shareLocationCapturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}share_location_captured_at'],
      ),
      ocrConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ocr_confidence'],
      ),
      rawOcrText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_ocr_text'],
      ),
      ocrServiceConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}ocr_service_confidence'],
      ),
      lineItemsConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}line_items_confidence'],
      ),
      parseFailureReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parse_failure_reason'],
      ),
      pipelineStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pipeline_status'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      ritualledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ritualled_at'],
      ),
      merchantCandidatesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}merchant_candidates_json'],
      ),
      ocrHeaderText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ocr_header_text'],
      ),
    );
  }

  @override
  $OutboxTransactionsTable createAlias(String alias) {
    return $OutboxTransactionsTable(attachedDatabase, alias);
  }
}

class OutboxTransaction extends DataClass
    implements Insertable<OutboxTransaction> {
  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime occurredAt;
  final double? amountMyr;
  final String? amountSource;
  final bool needsAmount;
  final String? merchantRaw;
  final String? merchantNormalized;
  final String? categoryGuess;
  final String? categoryUser;
  final double? categoryConfidence;

  /// User override for the derived impact level ('low'|'med'|'high'); null
  /// means the level shown in [TransactionView.effectiveImpactLevel] is
  /// re-derived from [amountMyr] rather than stored here.
  final String? impactUser;
  final String placeStatus;
  final String? placeGooglePlaceId;
  final String? placeName;
  final double? placeLat;
  final double? placeLng;
  final double? placeConfidence;
  final double? shareLocationLat;
  final double? shareLocationLng;
  final DateTime? shareLocationCapturedAt;
  final double? ocrConfidence;

  /// Raw OCR text, kept only when the parse failed or was low-confidence —
  /// the evidence needed to fix parser rules later.
  final String? rawOcrText;

  /// OCR engine's scan-quality confidence (mean word confidence, 0..1).
  /// Distinct from [ocrConfidence], which scores the amount *extraction*.
  final double? ocrServiceConfidence;

  /// Aggregate confidence over extracted line items.
  final double? lineItemsConfidence;

  /// Machine-readable reason when amount parsing failed outright.
  final String? parseFailureReason;
  final String pipelineStatus;
  final String syncStatus;
  final String? lastError;
  final int retryCount;

  /// Set after the receipt has been shown in the ritual animation.
  final DateTime? ritualledAt;

  /// Ranked merchant-name candidates (JSON-encoded `MerchantCandidate` list),
  /// synced to `transactions.merchant_candidates` (jsonb) so enrichment can
  /// try more than one Places text-search query.
  final String? merchantCandidatesJson;

  /// Top-of-receipt OCR lines, always populated (unlike [rawOcrText], which
  /// is review-only) — extra context for merchant/place enrichment.
  final String? ocrHeaderText;
  const OutboxTransaction({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.occurredAt,
    this.amountMyr,
    this.amountSource,
    required this.needsAmount,
    this.merchantRaw,
    this.merchantNormalized,
    this.categoryGuess,
    this.categoryUser,
    this.categoryConfidence,
    this.impactUser,
    required this.placeStatus,
    this.placeGooglePlaceId,
    this.placeName,
    this.placeLat,
    this.placeLng,
    this.placeConfidence,
    this.shareLocationLat,
    this.shareLocationLng,
    this.shareLocationCapturedAt,
    this.ocrConfidence,
    this.rawOcrText,
    this.ocrServiceConfidence,
    this.lineItemsConfidence,
    this.parseFailureReason,
    required this.pipelineStatus,
    required this.syncStatus,
    this.lastError,
    required this.retryCount,
    this.ritualledAt,
    this.merchantCandidatesJson,
    this.ocrHeaderText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || amountMyr != null) {
      map['amount_myr'] = Variable<double>(amountMyr);
    }
    if (!nullToAbsent || amountSource != null) {
      map['amount_source'] = Variable<String>(amountSource);
    }
    map['needs_amount'] = Variable<bool>(needsAmount);
    if (!nullToAbsent || merchantRaw != null) {
      map['merchant_raw'] = Variable<String>(merchantRaw);
    }
    if (!nullToAbsent || merchantNormalized != null) {
      map['merchant_normalized'] = Variable<String>(merchantNormalized);
    }
    if (!nullToAbsent || categoryGuess != null) {
      map['category_guess'] = Variable<String>(categoryGuess);
    }
    if (!nullToAbsent || categoryUser != null) {
      map['category_user'] = Variable<String>(categoryUser);
    }
    if (!nullToAbsent || categoryConfidence != null) {
      map['category_confidence'] = Variable<double>(categoryConfidence);
    }
    if (!nullToAbsent || impactUser != null) {
      map['impact_user'] = Variable<String>(impactUser);
    }
    map['place_status'] = Variable<String>(placeStatus);
    if (!nullToAbsent || placeGooglePlaceId != null) {
      map['place_google_place_id'] = Variable<String>(placeGooglePlaceId);
    }
    if (!nullToAbsent || placeName != null) {
      map['place_name'] = Variable<String>(placeName);
    }
    if (!nullToAbsent || placeLat != null) {
      map['place_lat'] = Variable<double>(placeLat);
    }
    if (!nullToAbsent || placeLng != null) {
      map['place_lng'] = Variable<double>(placeLng);
    }
    if (!nullToAbsent || placeConfidence != null) {
      map['place_confidence'] = Variable<double>(placeConfidence);
    }
    if (!nullToAbsent || shareLocationLat != null) {
      map['share_location_lat'] = Variable<double>(shareLocationLat);
    }
    if (!nullToAbsent || shareLocationLng != null) {
      map['share_location_lng'] = Variable<double>(shareLocationLng);
    }
    if (!nullToAbsent || shareLocationCapturedAt != null) {
      map['share_location_captured_at'] = Variable<DateTime>(
        shareLocationCapturedAt,
      );
    }
    if (!nullToAbsent || ocrConfidence != null) {
      map['ocr_confidence'] = Variable<double>(ocrConfidence);
    }
    if (!nullToAbsent || rawOcrText != null) {
      map['raw_ocr_text'] = Variable<String>(rawOcrText);
    }
    if (!nullToAbsent || ocrServiceConfidence != null) {
      map['ocr_service_confidence'] = Variable<double>(ocrServiceConfidence);
    }
    if (!nullToAbsent || lineItemsConfidence != null) {
      map['line_items_confidence'] = Variable<double>(lineItemsConfidence);
    }
    if (!nullToAbsent || parseFailureReason != null) {
      map['parse_failure_reason'] = Variable<String>(parseFailureReason);
    }
    map['pipeline_status'] = Variable<String>(pipelineStatus);
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || ritualledAt != null) {
      map['ritualled_at'] = Variable<DateTime>(ritualledAt);
    }
    if (!nullToAbsent || merchantCandidatesJson != null) {
      map['merchant_candidates_json'] = Variable<String>(
        merchantCandidatesJson,
      );
    }
    if (!nullToAbsent || ocrHeaderText != null) {
      map['ocr_header_text'] = Variable<String>(ocrHeaderText);
    }
    return map;
  }

  OutboxTransactionsCompanion toCompanion(bool nullToAbsent) {
    return OutboxTransactionsCompanion(
      id: Value(id),
      userId: Value(userId),
      createdAt: Value(createdAt),
      occurredAt: Value(occurredAt),
      amountMyr: amountMyr == null && nullToAbsent
          ? const Value.absent()
          : Value(amountMyr),
      amountSource: amountSource == null && nullToAbsent
          ? const Value.absent()
          : Value(amountSource),
      needsAmount: Value(needsAmount),
      merchantRaw: merchantRaw == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantRaw),
      merchantNormalized: merchantNormalized == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantNormalized),
      categoryGuess: categoryGuess == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryGuess),
      categoryUser: categoryUser == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryUser),
      categoryConfidence: categoryConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryConfidence),
      impactUser: impactUser == null && nullToAbsent
          ? const Value.absent()
          : Value(impactUser),
      placeStatus: Value(placeStatus),
      placeGooglePlaceId: placeGooglePlaceId == null && nullToAbsent
          ? const Value.absent()
          : Value(placeGooglePlaceId),
      placeName: placeName == null && nullToAbsent
          ? const Value.absent()
          : Value(placeName),
      placeLat: placeLat == null && nullToAbsent
          ? const Value.absent()
          : Value(placeLat),
      placeLng: placeLng == null && nullToAbsent
          ? const Value.absent()
          : Value(placeLng),
      placeConfidence: placeConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(placeConfidence),
      shareLocationLat: shareLocationLat == null && nullToAbsent
          ? const Value.absent()
          : Value(shareLocationLat),
      shareLocationLng: shareLocationLng == null && nullToAbsent
          ? const Value.absent()
          : Value(shareLocationLng),
      shareLocationCapturedAt: shareLocationCapturedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(shareLocationCapturedAt),
      ocrConfidence: ocrConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrConfidence),
      rawOcrText: rawOcrText == null && nullToAbsent
          ? const Value.absent()
          : Value(rawOcrText),
      ocrServiceConfidence: ocrServiceConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrServiceConfidence),
      lineItemsConfidence: lineItemsConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(lineItemsConfidence),
      parseFailureReason: parseFailureReason == null && nullToAbsent
          ? const Value.absent()
          : Value(parseFailureReason),
      pipelineStatus: Value(pipelineStatus),
      syncStatus: Value(syncStatus),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      retryCount: Value(retryCount),
      ritualledAt: ritualledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(ritualledAt),
      merchantCandidatesJson: merchantCandidatesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(merchantCandidatesJson),
      ocrHeaderText: ocrHeaderText == null && nullToAbsent
          ? const Value.absent()
          : Value(ocrHeaderText),
    );
  }

  factory OutboxTransaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxTransaction(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      amountMyr: serializer.fromJson<double?>(json['amountMyr']),
      amountSource: serializer.fromJson<String?>(json['amountSource']),
      needsAmount: serializer.fromJson<bool>(json['needsAmount']),
      merchantRaw: serializer.fromJson<String?>(json['merchantRaw']),
      merchantNormalized: serializer.fromJson<String?>(
        json['merchantNormalized'],
      ),
      categoryGuess: serializer.fromJson<String?>(json['categoryGuess']),
      categoryUser: serializer.fromJson<String?>(json['categoryUser']),
      categoryConfidence: serializer.fromJson<double?>(
        json['categoryConfidence'],
      ),
      impactUser: serializer.fromJson<String?>(json['impactUser']),
      placeStatus: serializer.fromJson<String>(json['placeStatus']),
      placeGooglePlaceId: serializer.fromJson<String?>(
        json['placeGooglePlaceId'],
      ),
      placeName: serializer.fromJson<String?>(json['placeName']),
      placeLat: serializer.fromJson<double?>(json['placeLat']),
      placeLng: serializer.fromJson<double?>(json['placeLng']),
      placeConfidence: serializer.fromJson<double?>(json['placeConfidence']),
      shareLocationLat: serializer.fromJson<double?>(json['shareLocationLat']),
      shareLocationLng: serializer.fromJson<double?>(json['shareLocationLng']),
      shareLocationCapturedAt: serializer.fromJson<DateTime?>(
        json['shareLocationCapturedAt'],
      ),
      ocrConfidence: serializer.fromJson<double?>(json['ocrConfidence']),
      rawOcrText: serializer.fromJson<String?>(json['rawOcrText']),
      ocrServiceConfidence: serializer.fromJson<double?>(
        json['ocrServiceConfidence'],
      ),
      lineItemsConfidence: serializer.fromJson<double?>(
        json['lineItemsConfidence'],
      ),
      parseFailureReason: serializer.fromJson<String?>(
        json['parseFailureReason'],
      ),
      pipelineStatus: serializer.fromJson<String>(json['pipelineStatus']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      ritualledAt: serializer.fromJson<DateTime?>(json['ritualledAt']),
      merchantCandidatesJson: serializer.fromJson<String?>(
        json['merchantCandidatesJson'],
      ),
      ocrHeaderText: serializer.fromJson<String?>(json['ocrHeaderText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'amountMyr': serializer.toJson<double?>(amountMyr),
      'amountSource': serializer.toJson<String?>(amountSource),
      'needsAmount': serializer.toJson<bool>(needsAmount),
      'merchantRaw': serializer.toJson<String?>(merchantRaw),
      'merchantNormalized': serializer.toJson<String?>(merchantNormalized),
      'categoryGuess': serializer.toJson<String?>(categoryGuess),
      'categoryUser': serializer.toJson<String?>(categoryUser),
      'categoryConfidence': serializer.toJson<double?>(categoryConfidence),
      'impactUser': serializer.toJson<String?>(impactUser),
      'placeStatus': serializer.toJson<String>(placeStatus),
      'placeGooglePlaceId': serializer.toJson<String?>(placeGooglePlaceId),
      'placeName': serializer.toJson<String?>(placeName),
      'placeLat': serializer.toJson<double?>(placeLat),
      'placeLng': serializer.toJson<double?>(placeLng),
      'placeConfidence': serializer.toJson<double?>(placeConfidence),
      'shareLocationLat': serializer.toJson<double?>(shareLocationLat),
      'shareLocationLng': serializer.toJson<double?>(shareLocationLng),
      'shareLocationCapturedAt': serializer.toJson<DateTime?>(
        shareLocationCapturedAt,
      ),
      'ocrConfidence': serializer.toJson<double?>(ocrConfidence),
      'rawOcrText': serializer.toJson<String?>(rawOcrText),
      'ocrServiceConfidence': serializer.toJson<double?>(ocrServiceConfidence),
      'lineItemsConfidence': serializer.toJson<double?>(lineItemsConfidence),
      'parseFailureReason': serializer.toJson<String?>(parseFailureReason),
      'pipelineStatus': serializer.toJson<String>(pipelineStatus),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'lastError': serializer.toJson<String?>(lastError),
      'retryCount': serializer.toJson<int>(retryCount),
      'ritualledAt': serializer.toJson<DateTime?>(ritualledAt),
      'merchantCandidatesJson': serializer.toJson<String?>(
        merchantCandidatesJson,
      ),
      'ocrHeaderText': serializer.toJson<String?>(ocrHeaderText),
    };
  }

  OutboxTransaction copyWith({
    String? id,
    String? userId,
    DateTime? createdAt,
    DateTime? occurredAt,
    Value<double?> amountMyr = const Value.absent(),
    Value<String?> amountSource = const Value.absent(),
    bool? needsAmount,
    Value<String?> merchantRaw = const Value.absent(),
    Value<String?> merchantNormalized = const Value.absent(),
    Value<String?> categoryGuess = const Value.absent(),
    Value<String?> categoryUser = const Value.absent(),
    Value<double?> categoryConfidence = const Value.absent(),
    Value<String?> impactUser = const Value.absent(),
    String? placeStatus,
    Value<String?> placeGooglePlaceId = const Value.absent(),
    Value<String?> placeName = const Value.absent(),
    Value<double?> placeLat = const Value.absent(),
    Value<double?> placeLng = const Value.absent(),
    Value<double?> placeConfidence = const Value.absent(),
    Value<double?> shareLocationLat = const Value.absent(),
    Value<double?> shareLocationLng = const Value.absent(),
    Value<DateTime?> shareLocationCapturedAt = const Value.absent(),
    Value<double?> ocrConfidence = const Value.absent(),
    Value<String?> rawOcrText = const Value.absent(),
    Value<double?> ocrServiceConfidence = const Value.absent(),
    Value<double?> lineItemsConfidence = const Value.absent(),
    Value<String?> parseFailureReason = const Value.absent(),
    String? pipelineStatus,
    String? syncStatus,
    Value<String?> lastError = const Value.absent(),
    int? retryCount,
    Value<DateTime?> ritualledAt = const Value.absent(),
    Value<String?> merchantCandidatesJson = const Value.absent(),
    Value<String?> ocrHeaderText = const Value.absent(),
  }) => OutboxTransaction(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    createdAt: createdAt ?? this.createdAt,
    occurredAt: occurredAt ?? this.occurredAt,
    amountMyr: amountMyr.present ? amountMyr.value : this.amountMyr,
    amountSource: amountSource.present ? amountSource.value : this.amountSource,
    needsAmount: needsAmount ?? this.needsAmount,
    merchantRaw: merchantRaw.present ? merchantRaw.value : this.merchantRaw,
    merchantNormalized: merchantNormalized.present
        ? merchantNormalized.value
        : this.merchantNormalized,
    categoryGuess: categoryGuess.present
        ? categoryGuess.value
        : this.categoryGuess,
    categoryUser: categoryUser.present ? categoryUser.value : this.categoryUser,
    categoryConfidence: categoryConfidence.present
        ? categoryConfidence.value
        : this.categoryConfidence,
    impactUser: impactUser.present ? impactUser.value : this.impactUser,
    placeStatus: placeStatus ?? this.placeStatus,
    placeGooglePlaceId: placeGooglePlaceId.present
        ? placeGooglePlaceId.value
        : this.placeGooglePlaceId,
    placeName: placeName.present ? placeName.value : this.placeName,
    placeLat: placeLat.present ? placeLat.value : this.placeLat,
    placeLng: placeLng.present ? placeLng.value : this.placeLng,
    placeConfidence: placeConfidence.present
        ? placeConfidence.value
        : this.placeConfidence,
    shareLocationLat: shareLocationLat.present
        ? shareLocationLat.value
        : this.shareLocationLat,
    shareLocationLng: shareLocationLng.present
        ? shareLocationLng.value
        : this.shareLocationLng,
    shareLocationCapturedAt: shareLocationCapturedAt.present
        ? shareLocationCapturedAt.value
        : this.shareLocationCapturedAt,
    ocrConfidence: ocrConfidence.present
        ? ocrConfidence.value
        : this.ocrConfidence,
    rawOcrText: rawOcrText.present ? rawOcrText.value : this.rawOcrText,
    ocrServiceConfidence: ocrServiceConfidence.present
        ? ocrServiceConfidence.value
        : this.ocrServiceConfidence,
    lineItemsConfidence: lineItemsConfidence.present
        ? lineItemsConfidence.value
        : this.lineItemsConfidence,
    parseFailureReason: parseFailureReason.present
        ? parseFailureReason.value
        : this.parseFailureReason,
    pipelineStatus: pipelineStatus ?? this.pipelineStatus,
    syncStatus: syncStatus ?? this.syncStatus,
    lastError: lastError.present ? lastError.value : this.lastError,
    retryCount: retryCount ?? this.retryCount,
    ritualledAt: ritualledAt.present ? ritualledAt.value : this.ritualledAt,
    merchantCandidatesJson: merchantCandidatesJson.present
        ? merchantCandidatesJson.value
        : this.merchantCandidatesJson,
    ocrHeaderText: ocrHeaderText.present
        ? ocrHeaderText.value
        : this.ocrHeaderText,
  );
  OutboxTransaction copyWithCompanion(OutboxTransactionsCompanion data) {
    return OutboxTransaction(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      amountMyr: data.amountMyr.present ? data.amountMyr.value : this.amountMyr,
      amountSource: data.amountSource.present
          ? data.amountSource.value
          : this.amountSource,
      needsAmount: data.needsAmount.present
          ? data.needsAmount.value
          : this.needsAmount,
      merchantRaw: data.merchantRaw.present
          ? data.merchantRaw.value
          : this.merchantRaw,
      merchantNormalized: data.merchantNormalized.present
          ? data.merchantNormalized.value
          : this.merchantNormalized,
      categoryGuess: data.categoryGuess.present
          ? data.categoryGuess.value
          : this.categoryGuess,
      categoryUser: data.categoryUser.present
          ? data.categoryUser.value
          : this.categoryUser,
      categoryConfidence: data.categoryConfidence.present
          ? data.categoryConfidence.value
          : this.categoryConfidence,
      impactUser: data.impactUser.present
          ? data.impactUser.value
          : this.impactUser,
      placeStatus: data.placeStatus.present
          ? data.placeStatus.value
          : this.placeStatus,
      placeGooglePlaceId: data.placeGooglePlaceId.present
          ? data.placeGooglePlaceId.value
          : this.placeGooglePlaceId,
      placeName: data.placeName.present ? data.placeName.value : this.placeName,
      placeLat: data.placeLat.present ? data.placeLat.value : this.placeLat,
      placeLng: data.placeLng.present ? data.placeLng.value : this.placeLng,
      placeConfidence: data.placeConfidence.present
          ? data.placeConfidence.value
          : this.placeConfidence,
      shareLocationLat: data.shareLocationLat.present
          ? data.shareLocationLat.value
          : this.shareLocationLat,
      shareLocationLng: data.shareLocationLng.present
          ? data.shareLocationLng.value
          : this.shareLocationLng,
      shareLocationCapturedAt: data.shareLocationCapturedAt.present
          ? data.shareLocationCapturedAt.value
          : this.shareLocationCapturedAt,
      ocrConfidence: data.ocrConfidence.present
          ? data.ocrConfidence.value
          : this.ocrConfidence,
      rawOcrText: data.rawOcrText.present
          ? data.rawOcrText.value
          : this.rawOcrText,
      ocrServiceConfidence: data.ocrServiceConfidence.present
          ? data.ocrServiceConfidence.value
          : this.ocrServiceConfidence,
      lineItemsConfidence: data.lineItemsConfidence.present
          ? data.lineItemsConfidence.value
          : this.lineItemsConfidence,
      parseFailureReason: data.parseFailureReason.present
          ? data.parseFailureReason.value
          : this.parseFailureReason,
      pipelineStatus: data.pipelineStatus.present
          ? data.pipelineStatus.value
          : this.pipelineStatus,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      ritualledAt: data.ritualledAt.present
          ? data.ritualledAt.value
          : this.ritualledAt,
      merchantCandidatesJson: data.merchantCandidatesJson.present
          ? data.merchantCandidatesJson.value
          : this.merchantCandidatesJson,
      ocrHeaderText: data.ocrHeaderText.present
          ? data.ocrHeaderText.value
          : this.ocrHeaderText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxTransaction(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('amountMyr: $amountMyr, ')
          ..write('amountSource: $amountSource, ')
          ..write('needsAmount: $needsAmount, ')
          ..write('merchantRaw: $merchantRaw, ')
          ..write('merchantNormalized: $merchantNormalized, ')
          ..write('categoryGuess: $categoryGuess, ')
          ..write('categoryUser: $categoryUser, ')
          ..write('categoryConfidence: $categoryConfidence, ')
          ..write('impactUser: $impactUser, ')
          ..write('placeStatus: $placeStatus, ')
          ..write('placeGooglePlaceId: $placeGooglePlaceId, ')
          ..write('placeName: $placeName, ')
          ..write('placeLat: $placeLat, ')
          ..write('placeLng: $placeLng, ')
          ..write('placeConfidence: $placeConfidence, ')
          ..write('shareLocationLat: $shareLocationLat, ')
          ..write('shareLocationLng: $shareLocationLng, ')
          ..write('shareLocationCapturedAt: $shareLocationCapturedAt, ')
          ..write('ocrConfidence: $ocrConfidence, ')
          ..write('rawOcrText: $rawOcrText, ')
          ..write('ocrServiceConfidence: $ocrServiceConfidence, ')
          ..write('lineItemsConfidence: $lineItemsConfidence, ')
          ..write('parseFailureReason: $parseFailureReason, ')
          ..write('pipelineStatus: $pipelineStatus, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastError: $lastError, ')
          ..write('retryCount: $retryCount, ')
          ..write('ritualledAt: $ritualledAt, ')
          ..write('merchantCandidatesJson: $merchantCandidatesJson, ')
          ..write('ocrHeaderText: $ocrHeaderText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    userId,
    createdAt,
    occurredAt,
    amountMyr,
    amountSource,
    needsAmount,
    merchantRaw,
    merchantNormalized,
    categoryGuess,
    categoryUser,
    categoryConfidence,
    impactUser,
    placeStatus,
    placeGooglePlaceId,
    placeName,
    placeLat,
    placeLng,
    placeConfidence,
    shareLocationLat,
    shareLocationLng,
    shareLocationCapturedAt,
    ocrConfidence,
    rawOcrText,
    ocrServiceConfidence,
    lineItemsConfidence,
    parseFailureReason,
    pipelineStatus,
    syncStatus,
    lastError,
    retryCount,
    ritualledAt,
    merchantCandidatesJson,
    ocrHeaderText,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxTransaction &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.createdAt == this.createdAt &&
          other.occurredAt == this.occurredAt &&
          other.amountMyr == this.amountMyr &&
          other.amountSource == this.amountSource &&
          other.needsAmount == this.needsAmount &&
          other.merchantRaw == this.merchantRaw &&
          other.merchantNormalized == this.merchantNormalized &&
          other.categoryGuess == this.categoryGuess &&
          other.categoryUser == this.categoryUser &&
          other.categoryConfidence == this.categoryConfidence &&
          other.impactUser == this.impactUser &&
          other.placeStatus == this.placeStatus &&
          other.placeGooglePlaceId == this.placeGooglePlaceId &&
          other.placeName == this.placeName &&
          other.placeLat == this.placeLat &&
          other.placeLng == this.placeLng &&
          other.placeConfidence == this.placeConfidence &&
          other.shareLocationLat == this.shareLocationLat &&
          other.shareLocationLng == this.shareLocationLng &&
          other.shareLocationCapturedAt == this.shareLocationCapturedAt &&
          other.ocrConfidence == this.ocrConfidence &&
          other.rawOcrText == this.rawOcrText &&
          other.ocrServiceConfidence == this.ocrServiceConfidence &&
          other.lineItemsConfidence == this.lineItemsConfidence &&
          other.parseFailureReason == this.parseFailureReason &&
          other.pipelineStatus == this.pipelineStatus &&
          other.syncStatus == this.syncStatus &&
          other.lastError == this.lastError &&
          other.retryCount == this.retryCount &&
          other.ritualledAt == this.ritualledAt &&
          other.merchantCandidatesJson == this.merchantCandidatesJson &&
          other.ocrHeaderText == this.ocrHeaderText);
}

class OutboxTransactionsCompanion extends UpdateCompanion<OutboxTransaction> {
  final Value<String> id;
  final Value<String> userId;
  final Value<DateTime> createdAt;
  final Value<DateTime> occurredAt;
  final Value<double?> amountMyr;
  final Value<String?> amountSource;
  final Value<bool> needsAmount;
  final Value<String?> merchantRaw;
  final Value<String?> merchantNormalized;
  final Value<String?> categoryGuess;
  final Value<String?> categoryUser;
  final Value<double?> categoryConfidence;
  final Value<String?> impactUser;
  final Value<String> placeStatus;
  final Value<String?> placeGooglePlaceId;
  final Value<String?> placeName;
  final Value<double?> placeLat;
  final Value<double?> placeLng;
  final Value<double?> placeConfidence;
  final Value<double?> shareLocationLat;
  final Value<double?> shareLocationLng;
  final Value<DateTime?> shareLocationCapturedAt;
  final Value<double?> ocrConfidence;
  final Value<String?> rawOcrText;
  final Value<double?> ocrServiceConfidence;
  final Value<double?> lineItemsConfidence;
  final Value<String?> parseFailureReason;
  final Value<String> pipelineStatus;
  final Value<String> syncStatus;
  final Value<String?> lastError;
  final Value<int> retryCount;
  final Value<DateTime?> ritualledAt;
  final Value<String?> merchantCandidatesJson;
  final Value<String?> ocrHeaderText;
  final Value<int> rowid;
  const OutboxTransactionsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.amountMyr = const Value.absent(),
    this.amountSource = const Value.absent(),
    this.needsAmount = const Value.absent(),
    this.merchantRaw = const Value.absent(),
    this.merchantNormalized = const Value.absent(),
    this.categoryGuess = const Value.absent(),
    this.categoryUser = const Value.absent(),
    this.categoryConfidence = const Value.absent(),
    this.impactUser = const Value.absent(),
    this.placeStatus = const Value.absent(),
    this.placeGooglePlaceId = const Value.absent(),
    this.placeName = const Value.absent(),
    this.placeLat = const Value.absent(),
    this.placeLng = const Value.absent(),
    this.placeConfidence = const Value.absent(),
    this.shareLocationLat = const Value.absent(),
    this.shareLocationLng = const Value.absent(),
    this.shareLocationCapturedAt = const Value.absent(),
    this.ocrConfidence = const Value.absent(),
    this.rawOcrText = const Value.absent(),
    this.ocrServiceConfidence = const Value.absent(),
    this.lineItemsConfidence = const Value.absent(),
    this.parseFailureReason = const Value.absent(),
    this.pipelineStatus = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastError = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.ritualledAt = const Value.absent(),
    this.merchantCandidatesJson = const Value.absent(),
    this.ocrHeaderText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxTransactionsCompanion.insert({
    required String id,
    required String userId,
    this.createdAt = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.amountMyr = const Value.absent(),
    this.amountSource = const Value.absent(),
    this.needsAmount = const Value.absent(),
    this.merchantRaw = const Value.absent(),
    this.merchantNormalized = const Value.absent(),
    this.categoryGuess = const Value.absent(),
    this.categoryUser = const Value.absent(),
    this.categoryConfidence = const Value.absent(),
    this.impactUser = const Value.absent(),
    this.placeStatus = const Value.absent(),
    this.placeGooglePlaceId = const Value.absent(),
    this.placeName = const Value.absent(),
    this.placeLat = const Value.absent(),
    this.placeLng = const Value.absent(),
    this.placeConfidence = const Value.absent(),
    this.shareLocationLat = const Value.absent(),
    this.shareLocationLng = const Value.absent(),
    this.shareLocationCapturedAt = const Value.absent(),
    this.ocrConfidence = const Value.absent(),
    this.rawOcrText = const Value.absent(),
    this.ocrServiceConfidence = const Value.absent(),
    this.lineItemsConfidence = const Value.absent(),
    this.parseFailureReason = const Value.absent(),
    this.pipelineStatus = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.lastError = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.ritualledAt = const Value.absent(),
    this.merchantCandidatesJson = const Value.absent(),
    this.ocrHeaderText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId);
  static Insertable<OutboxTransaction> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? occurredAt,
    Expression<double>? amountMyr,
    Expression<String>? amountSource,
    Expression<bool>? needsAmount,
    Expression<String>? merchantRaw,
    Expression<String>? merchantNormalized,
    Expression<String>? categoryGuess,
    Expression<String>? categoryUser,
    Expression<double>? categoryConfidence,
    Expression<String>? impactUser,
    Expression<String>? placeStatus,
    Expression<String>? placeGooglePlaceId,
    Expression<String>? placeName,
    Expression<double>? placeLat,
    Expression<double>? placeLng,
    Expression<double>? placeConfidence,
    Expression<double>? shareLocationLat,
    Expression<double>? shareLocationLng,
    Expression<DateTime>? shareLocationCapturedAt,
    Expression<double>? ocrConfidence,
    Expression<String>? rawOcrText,
    Expression<double>? ocrServiceConfidence,
    Expression<double>? lineItemsConfidence,
    Expression<String>? parseFailureReason,
    Expression<String>? pipelineStatus,
    Expression<String>? syncStatus,
    Expression<String>? lastError,
    Expression<int>? retryCount,
    Expression<DateTime>? ritualledAt,
    Expression<String>? merchantCandidatesJson,
    Expression<String>? ocrHeaderText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (createdAt != null) 'created_at': createdAt,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (amountMyr != null) 'amount_myr': amountMyr,
      if (amountSource != null) 'amount_source': amountSource,
      if (needsAmount != null) 'needs_amount': needsAmount,
      if (merchantRaw != null) 'merchant_raw': merchantRaw,
      if (merchantNormalized != null) 'merchant_normalized': merchantNormalized,
      if (categoryGuess != null) 'category_guess': categoryGuess,
      if (categoryUser != null) 'category_user': categoryUser,
      if (categoryConfidence != null) 'category_confidence': categoryConfidence,
      if (impactUser != null) 'impact_user': impactUser,
      if (placeStatus != null) 'place_status': placeStatus,
      if (placeGooglePlaceId != null)
        'place_google_place_id': placeGooglePlaceId,
      if (placeName != null) 'place_name': placeName,
      if (placeLat != null) 'place_lat': placeLat,
      if (placeLng != null) 'place_lng': placeLng,
      if (placeConfidence != null) 'place_confidence': placeConfidence,
      if (shareLocationLat != null) 'share_location_lat': shareLocationLat,
      if (shareLocationLng != null) 'share_location_lng': shareLocationLng,
      if (shareLocationCapturedAt != null)
        'share_location_captured_at': shareLocationCapturedAt,
      if (ocrConfidence != null) 'ocr_confidence': ocrConfidence,
      if (rawOcrText != null) 'raw_ocr_text': rawOcrText,
      if (ocrServiceConfidence != null)
        'ocr_service_confidence': ocrServiceConfidence,
      if (lineItemsConfidence != null)
        'line_items_confidence': lineItemsConfidence,
      if (parseFailureReason != null)
        'parse_failure_reason': parseFailureReason,
      if (pipelineStatus != null) 'pipeline_status': pipelineStatus,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (lastError != null) 'last_error': lastError,
      if (retryCount != null) 'retry_count': retryCount,
      if (ritualledAt != null) 'ritualled_at': ritualledAt,
      if (merchantCandidatesJson != null)
        'merchant_candidates_json': merchantCandidatesJson,
      if (ocrHeaderText != null) 'ocr_header_text': ocrHeaderText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxTransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<DateTime>? createdAt,
    Value<DateTime>? occurredAt,
    Value<double?>? amountMyr,
    Value<String?>? amountSource,
    Value<bool>? needsAmount,
    Value<String?>? merchantRaw,
    Value<String?>? merchantNormalized,
    Value<String?>? categoryGuess,
    Value<String?>? categoryUser,
    Value<double?>? categoryConfidence,
    Value<String?>? impactUser,
    Value<String>? placeStatus,
    Value<String?>? placeGooglePlaceId,
    Value<String?>? placeName,
    Value<double?>? placeLat,
    Value<double?>? placeLng,
    Value<double?>? placeConfidence,
    Value<double?>? shareLocationLat,
    Value<double?>? shareLocationLng,
    Value<DateTime?>? shareLocationCapturedAt,
    Value<double?>? ocrConfidence,
    Value<String?>? rawOcrText,
    Value<double?>? ocrServiceConfidence,
    Value<double?>? lineItemsConfidence,
    Value<String?>? parseFailureReason,
    Value<String>? pipelineStatus,
    Value<String>? syncStatus,
    Value<String?>? lastError,
    Value<int>? retryCount,
    Value<DateTime?>? ritualledAt,
    Value<String?>? merchantCandidatesJson,
    Value<String?>? ocrHeaderText,
    Value<int>? rowid,
  }) {
    return OutboxTransactionsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      occurredAt: occurredAt ?? this.occurredAt,
      amountMyr: amountMyr ?? this.amountMyr,
      amountSource: amountSource ?? this.amountSource,
      needsAmount: needsAmount ?? this.needsAmount,
      merchantRaw: merchantRaw ?? this.merchantRaw,
      merchantNormalized: merchantNormalized ?? this.merchantNormalized,
      categoryGuess: categoryGuess ?? this.categoryGuess,
      categoryUser: categoryUser ?? this.categoryUser,
      categoryConfidence: categoryConfidence ?? this.categoryConfidence,
      impactUser: impactUser ?? this.impactUser,
      placeStatus: placeStatus ?? this.placeStatus,
      placeGooglePlaceId: placeGooglePlaceId ?? this.placeGooglePlaceId,
      placeName: placeName ?? this.placeName,
      placeLat: placeLat ?? this.placeLat,
      placeLng: placeLng ?? this.placeLng,
      placeConfidence: placeConfidence ?? this.placeConfidence,
      shareLocationLat: shareLocationLat ?? this.shareLocationLat,
      shareLocationLng: shareLocationLng ?? this.shareLocationLng,
      shareLocationCapturedAt:
          shareLocationCapturedAt ?? this.shareLocationCapturedAt,
      ocrConfidence: ocrConfidence ?? this.ocrConfidence,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      ocrServiceConfidence: ocrServiceConfidence ?? this.ocrServiceConfidence,
      lineItemsConfidence: lineItemsConfidence ?? this.lineItemsConfidence,
      parseFailureReason: parseFailureReason ?? this.parseFailureReason,
      pipelineStatus: pipelineStatus ?? this.pipelineStatus,
      syncStatus: syncStatus ?? this.syncStatus,
      lastError: lastError ?? this.lastError,
      retryCount: retryCount ?? this.retryCount,
      ritualledAt: ritualledAt ?? this.ritualledAt,
      merchantCandidatesJson:
          merchantCandidatesJson ?? this.merchantCandidatesJson,
      ocrHeaderText: ocrHeaderText ?? this.ocrHeaderText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (amountMyr.present) {
      map['amount_myr'] = Variable<double>(amountMyr.value);
    }
    if (amountSource.present) {
      map['amount_source'] = Variable<String>(amountSource.value);
    }
    if (needsAmount.present) {
      map['needs_amount'] = Variable<bool>(needsAmount.value);
    }
    if (merchantRaw.present) {
      map['merchant_raw'] = Variable<String>(merchantRaw.value);
    }
    if (merchantNormalized.present) {
      map['merchant_normalized'] = Variable<String>(merchantNormalized.value);
    }
    if (categoryGuess.present) {
      map['category_guess'] = Variable<String>(categoryGuess.value);
    }
    if (categoryUser.present) {
      map['category_user'] = Variable<String>(categoryUser.value);
    }
    if (categoryConfidence.present) {
      map['category_confidence'] = Variable<double>(categoryConfidence.value);
    }
    if (impactUser.present) {
      map['impact_user'] = Variable<String>(impactUser.value);
    }
    if (placeStatus.present) {
      map['place_status'] = Variable<String>(placeStatus.value);
    }
    if (placeGooglePlaceId.present) {
      map['place_google_place_id'] = Variable<String>(placeGooglePlaceId.value);
    }
    if (placeName.present) {
      map['place_name'] = Variable<String>(placeName.value);
    }
    if (placeLat.present) {
      map['place_lat'] = Variable<double>(placeLat.value);
    }
    if (placeLng.present) {
      map['place_lng'] = Variable<double>(placeLng.value);
    }
    if (placeConfidence.present) {
      map['place_confidence'] = Variable<double>(placeConfidence.value);
    }
    if (shareLocationLat.present) {
      map['share_location_lat'] = Variable<double>(shareLocationLat.value);
    }
    if (shareLocationLng.present) {
      map['share_location_lng'] = Variable<double>(shareLocationLng.value);
    }
    if (shareLocationCapturedAt.present) {
      map['share_location_captured_at'] = Variable<DateTime>(
        shareLocationCapturedAt.value,
      );
    }
    if (ocrConfidence.present) {
      map['ocr_confidence'] = Variable<double>(ocrConfidence.value);
    }
    if (rawOcrText.present) {
      map['raw_ocr_text'] = Variable<String>(rawOcrText.value);
    }
    if (ocrServiceConfidence.present) {
      map['ocr_service_confidence'] = Variable<double>(
        ocrServiceConfidence.value,
      );
    }
    if (lineItemsConfidence.present) {
      map['line_items_confidence'] = Variable<double>(
        lineItemsConfidence.value,
      );
    }
    if (parseFailureReason.present) {
      map['parse_failure_reason'] = Variable<String>(parseFailureReason.value);
    }
    if (pipelineStatus.present) {
      map['pipeline_status'] = Variable<String>(pipelineStatus.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (ritualledAt.present) {
      map['ritualled_at'] = Variable<DateTime>(ritualledAt.value);
    }
    if (merchantCandidatesJson.present) {
      map['merchant_candidates_json'] = Variable<String>(
        merchantCandidatesJson.value,
      );
    }
    if (ocrHeaderText.present) {
      map['ocr_header_text'] = Variable<String>(ocrHeaderText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('amountMyr: $amountMyr, ')
          ..write('amountSource: $amountSource, ')
          ..write('needsAmount: $needsAmount, ')
          ..write('merchantRaw: $merchantRaw, ')
          ..write('merchantNormalized: $merchantNormalized, ')
          ..write('categoryGuess: $categoryGuess, ')
          ..write('categoryUser: $categoryUser, ')
          ..write('categoryConfidence: $categoryConfidence, ')
          ..write('impactUser: $impactUser, ')
          ..write('placeStatus: $placeStatus, ')
          ..write('placeGooglePlaceId: $placeGooglePlaceId, ')
          ..write('placeName: $placeName, ')
          ..write('placeLat: $placeLat, ')
          ..write('placeLng: $placeLng, ')
          ..write('placeConfidence: $placeConfidence, ')
          ..write('shareLocationLat: $shareLocationLat, ')
          ..write('shareLocationLng: $shareLocationLng, ')
          ..write('shareLocationCapturedAt: $shareLocationCapturedAt, ')
          ..write('ocrConfidence: $ocrConfidence, ')
          ..write('rawOcrText: $rawOcrText, ')
          ..write('ocrServiceConfidence: $ocrServiceConfidence, ')
          ..write('lineItemsConfidence: $lineItemsConfidence, ')
          ..write('parseFailureReason: $parseFailureReason, ')
          ..write('pipelineStatus: $pipelineStatus, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('lastError: $lastError, ')
          ..write('retryCount: $retryCount, ')
          ..write('ritualledAt: $ritualledAt, ')
          ..write('merchantCandidatesJson: $merchantCandidatesJson, ')
          ..write('ocrHeaderText: $ocrHeaderText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxArtifactsTable extends OutboxArtifacts
    with TableInfo<$OutboxArtifactsTable, OutboxArtifact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxArtifactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES outbox_transactions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localFilePathMeta = const VerificationMeta(
    'localFilePath',
  );
  @override
  late final GeneratedColumn<String> localFilePath = GeneratedColumn<String>(
    'local_file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    transactionId,
    storagePath,
    mimeType,
    localFilePath,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_artifacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxArtifact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('local_file_path')) {
      context.handle(
        _localFilePathMeta,
        localFilePath.isAcceptableOrUnknown(
          data['local_file_path']!,
          _localFilePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localFilePathMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxArtifact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxArtifact(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      )!,
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      localFilePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_file_path'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxArtifactsTable createAlias(String alias) {
    return $OutboxArtifactsTable(attachedDatabase, alias);
  }
}

class OutboxArtifact extends DataClass implements Insertable<OutboxArtifact> {
  final String id;
  final String userId;
  final String transactionId;
  final String? storagePath;
  final String mimeType;
  final String localFilePath;
  final DateTime createdAt;
  const OutboxArtifact({
    required this.id,
    required this.userId,
    required this.transactionId,
    this.storagePath,
    required this.mimeType,
    required this.localFilePath,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['transaction_id'] = Variable<String>(transactionId);
    if (!nullToAbsent || storagePath != null) {
      map['storage_path'] = Variable<String>(storagePath);
    }
    map['mime_type'] = Variable<String>(mimeType);
    map['local_file_path'] = Variable<String>(localFilePath);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxArtifactsCompanion toCompanion(bool nullToAbsent) {
    return OutboxArtifactsCompanion(
      id: Value(id),
      userId: Value(userId),
      transactionId: Value(transactionId),
      storagePath: storagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(storagePath),
      mimeType: Value(mimeType),
      localFilePath: Value(localFilePath),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxArtifact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxArtifact(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      storagePath: serializer.fromJson<String?>(json['storagePath']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      localFilePath: serializer.fromJson<String>(json['localFilePath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'transactionId': serializer.toJson<String>(transactionId),
      'storagePath': serializer.toJson<String?>(storagePath),
      'mimeType': serializer.toJson<String>(mimeType),
      'localFilePath': serializer.toJson<String>(localFilePath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxArtifact copyWith({
    String? id,
    String? userId,
    String? transactionId,
    Value<String?> storagePath = const Value.absent(),
    String? mimeType,
    String? localFilePath,
    DateTime? createdAt,
  }) => OutboxArtifact(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    transactionId: transactionId ?? this.transactionId,
    storagePath: storagePath.present ? storagePath.value : this.storagePath,
    mimeType: mimeType ?? this.mimeType,
    localFilePath: localFilePath ?? this.localFilePath,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxArtifact copyWithCompanion(OutboxArtifactsCompanion data) {
    return OutboxArtifact(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      localFilePath: data.localFilePath.present
          ? data.localFilePath.value
          : this.localFilePath,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxArtifact(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('transactionId: $transactionId, ')
          ..write('storagePath: $storagePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    transactionId,
    storagePath,
    mimeType,
    localFilePath,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxArtifact &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.transactionId == this.transactionId &&
          other.storagePath == this.storagePath &&
          other.mimeType == this.mimeType &&
          other.localFilePath == this.localFilePath &&
          other.createdAt == this.createdAt);
}

class OutboxArtifactsCompanion extends UpdateCompanion<OutboxArtifact> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> transactionId;
  final Value<String?> storagePath;
  final Value<String> mimeType;
  final Value<String> localFilePath;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OutboxArtifactsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.localFilePath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxArtifactsCompanion.insert({
    required String id,
    required String userId,
    required String transactionId,
    this.storagePath = const Value.absent(),
    required String mimeType,
    required String localFilePath,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       transactionId = Value(transactionId),
       mimeType = Value(mimeType),
       localFilePath = Value(localFilePath);
  static Insertable<OutboxArtifact> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? transactionId,
    Expression<String>? storagePath,
    Expression<String>? mimeType,
    Expression<String>? localFilePath,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (storagePath != null) 'storage_path': storagePath,
      if (mimeType != null) 'mime_type': mimeType,
      if (localFilePath != null) 'local_file_path': localFilePath,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxArtifactsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? transactionId,
    Value<String?>? storagePath,
    Value<String>? mimeType,
    Value<String>? localFilePath,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OutboxArtifactsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      transactionId: transactionId ?? this.transactionId,
      storagePath: storagePath ?? this.storagePath,
      mimeType: mimeType ?? this.mimeType,
      localFilePath: localFilePath ?? this.localFilePath,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (localFilePath.present) {
      map['local_file_path'] = Variable<String>(localFilePath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxArtifactsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('transactionId: $transactionId, ')
          ..write('storagePath: $storagePath, ')
          ..write('mimeType: $mimeType, ')
          ..write('localFilePath: $localFilePath, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxLineItemsTable extends OutboxLineItems
    with TableInfo<$OutboxLineItemsTable, OutboxLineItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxLineItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES outbox_transactions (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceMyrMeta = const VerificationMeta(
    'priceMyr',
  );
  @override
  late final GeneratedColumn<double> priceMyr = GeneratedColumn<double>(
    'price_myr',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _quantityMeta = const VerificationMeta(
    'quantity',
  );
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
    'quantity',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    userId,
    transactionId,
    name,
    priceMyr,
    quantity,
    confidence,
    sortOrder,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_line_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxLineItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price_myr')) {
      context.handle(
        _priceMyrMeta,
        priceMyr.isAcceptableOrUnknown(data['price_myr']!, _priceMyrMeta),
      );
    } else if (isInserting) {
      context.missing(_priceMyrMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(
        _quantityMeta,
        quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxLineItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxLineItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      priceMyr: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}price_myr'],
      )!,
      quantity: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quantity'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $OutboxLineItemsTable createAlias(String alias) {
    return $OutboxLineItemsTable(attachedDatabase, alias);
  }
}

class OutboxLineItem extends DataClass implements Insertable<OutboxLineItem> {
  final String id;
  final String userId;
  final String transactionId;
  final String name;
  final double priceMyr;
  final int? quantity;
  final double? confidence;

  /// 0-based position in the parsed item list; SQLite doesn't guarantee row
  /// order, so this preserves the original OCR order on read.
  final int sortOrder;
  const OutboxLineItem({
    required this.id,
    required this.userId,
    required this.transactionId,
    required this.name,
    required this.priceMyr,
    this.quantity,
    this.confidence,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['user_id'] = Variable<String>(userId);
    map['transaction_id'] = Variable<String>(transactionId);
    map['name'] = Variable<String>(name);
    map['price_myr'] = Variable<double>(priceMyr);
    if (!nullToAbsent || quantity != null) {
      map['quantity'] = Variable<int>(quantity);
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  OutboxLineItemsCompanion toCompanion(bool nullToAbsent) {
    return OutboxLineItemsCompanion(
      id: Value(id),
      userId: Value(userId),
      transactionId: Value(transactionId),
      name: Value(name),
      priceMyr: Value(priceMyr),
      quantity: quantity == null && nullToAbsent
          ? const Value.absent()
          : Value(quantity),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      sortOrder: Value(sortOrder),
    );
  }

  factory OutboxLineItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxLineItem(
      id: serializer.fromJson<String>(json['id']),
      userId: serializer.fromJson<String>(json['userId']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      name: serializer.fromJson<String>(json['name']),
      priceMyr: serializer.fromJson<double>(json['priceMyr']),
      quantity: serializer.fromJson<int?>(json['quantity']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'userId': serializer.toJson<String>(userId),
      'transactionId': serializer.toJson<String>(transactionId),
      'name': serializer.toJson<String>(name),
      'priceMyr': serializer.toJson<double>(priceMyr),
      'quantity': serializer.toJson<int?>(quantity),
      'confidence': serializer.toJson<double?>(confidence),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  OutboxLineItem copyWith({
    String? id,
    String? userId,
    String? transactionId,
    String? name,
    double? priceMyr,
    Value<int?> quantity = const Value.absent(),
    Value<double?> confidence = const Value.absent(),
    int? sortOrder,
  }) => OutboxLineItem(
    id: id ?? this.id,
    userId: userId ?? this.userId,
    transactionId: transactionId ?? this.transactionId,
    name: name ?? this.name,
    priceMyr: priceMyr ?? this.priceMyr,
    quantity: quantity.present ? quantity.value : this.quantity,
    confidence: confidence.present ? confidence.value : this.confidence,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  OutboxLineItem copyWithCompanion(OutboxLineItemsCompanion data) {
    return OutboxLineItem(
      id: data.id.present ? data.id.value : this.id,
      userId: data.userId.present ? data.userId.value : this.userId,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      name: data.name.present ? data.name.value : this.name,
      priceMyr: data.priceMyr.present ? data.priceMyr.value : this.priceMyr,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxLineItem(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('transactionId: $transactionId, ')
          ..write('name: $name, ')
          ..write('priceMyr: $priceMyr, ')
          ..write('quantity: $quantity, ')
          ..write('confidence: $confidence, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    userId,
    transactionId,
    name,
    priceMyr,
    quantity,
    confidence,
    sortOrder,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxLineItem &&
          other.id == this.id &&
          other.userId == this.userId &&
          other.transactionId == this.transactionId &&
          other.name == this.name &&
          other.priceMyr == this.priceMyr &&
          other.quantity == this.quantity &&
          other.confidence == this.confidence &&
          other.sortOrder == this.sortOrder);
}

class OutboxLineItemsCompanion extends UpdateCompanion<OutboxLineItem> {
  final Value<String> id;
  final Value<String> userId;
  final Value<String> transactionId;
  final Value<String> name;
  final Value<double> priceMyr;
  final Value<int?> quantity;
  final Value<double?> confidence;
  final Value<int> sortOrder;
  final Value<int> rowid;
  const OutboxLineItemsCompanion({
    this.id = const Value.absent(),
    this.userId = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.name = const Value.absent(),
    this.priceMyr = const Value.absent(),
    this.quantity = const Value.absent(),
    this.confidence = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxLineItemsCompanion.insert({
    required String id,
    required String userId,
    required String transactionId,
    required String name,
    required double priceMyr,
    this.quantity = const Value.absent(),
    this.confidence = const Value.absent(),
    required int sortOrder,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       userId = Value(userId),
       transactionId = Value(transactionId),
       name = Value(name),
       priceMyr = Value(priceMyr),
       sortOrder = Value(sortOrder);
  static Insertable<OutboxLineItem> custom({
    Expression<String>? id,
    Expression<String>? userId,
    Expression<String>? transactionId,
    Expression<String>? name,
    Expression<double>? priceMyr,
    Expression<int>? quantity,
    Expression<double>? confidence,
    Expression<int>? sortOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (userId != null) 'user_id': userId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (name != null) 'name': name,
      if (priceMyr != null) 'price_myr': priceMyr,
      if (quantity != null) 'quantity': quantity,
      if (confidence != null) 'confidence': confidence,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxLineItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? userId,
    Value<String>? transactionId,
    Value<String>? name,
    Value<double>? priceMyr,
    Value<int?>? quantity,
    Value<double?>? confidence,
    Value<int>? sortOrder,
    Value<int>? rowid,
  }) {
    return OutboxLineItemsCompanion(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      transactionId: transactionId ?? this.transactionId,
      name: name ?? this.name,
      priceMyr: priceMyr ?? this.priceMyr,
      quantity: quantity ?? this.quantity,
      confidence: confidence ?? this.confidence,
      sortOrder: sortOrder ?? this.sortOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (priceMyr.present) {
      map['price_myr'] = Variable<double>(priceMyr.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxLineItemsCompanion(')
          ..write('id: $id, ')
          ..write('userId: $userId, ')
          ..write('transactionId: $transactionId, ')
          ..write('name: $name, ')
          ..write('priceMyr: $priceMyr, ')
          ..write('quantity: $quantity, ')
          ..write('confidence: $confidence, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoryConfigCacheTable extends CategoryConfigCache
    with TableInfo<$CategoryConfigCacheTable, CategoryConfigCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryConfigCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _jsonBodyMeta = const VerificationMeta(
    'jsonBody',
  );
  @override
  late final GeneratedColumn<String> jsonBody = GeneratedColumn<String>(
    'json_body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    version,
    etag,
    jsonBody,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_config_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryConfigCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('json_body')) {
      context.handle(
        _jsonBodyMeta,
        jsonBody.isAcceptableOrUnknown(data['json_body']!, _jsonBodyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryConfigCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryConfigCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      jsonBody: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json_body'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
    );
  }

  @override
  $CategoryConfigCacheTable createAlias(String alias) {
    return $CategoryConfigCacheTable(attachedDatabase, alias);
  }
}

class CategoryConfigCacheRow extends DataClass
    implements Insertable<CategoryConfigCacheRow> {
  final int id;
  final String? version;
  final String? etag;
  final String? jsonBody;
  final DateTime? updatedAt;
  const CategoryConfigCacheRow({
    required this.id,
    this.version,
    this.etag,
    this.jsonBody,
    this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || version != null) {
      map['version'] = Variable<String>(version);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || jsonBody != null) {
      map['json_body'] = Variable<String>(jsonBody);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    return map;
  }

  CategoryConfigCacheCompanion toCompanion(bool nullToAbsent) {
    return CategoryConfigCacheCompanion(
      id: Value(id),
      version: version == null && nullToAbsent
          ? const Value.absent()
          : Value(version),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      jsonBody: jsonBody == null && nullToAbsent
          ? const Value.absent()
          : Value(jsonBody),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
    );
  }

  factory CategoryConfigCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryConfigCacheRow(
      id: serializer.fromJson<int>(json['id']),
      version: serializer.fromJson<String?>(json['version']),
      etag: serializer.fromJson<String?>(json['etag']),
      jsonBody: serializer.fromJson<String?>(json['jsonBody']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'version': serializer.toJson<String?>(version),
      'etag': serializer.toJson<String?>(etag),
      'jsonBody': serializer.toJson<String?>(jsonBody),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
    };
  }

  CategoryConfigCacheRow copyWith({
    int? id,
    Value<String?> version = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    Value<String?> jsonBody = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
  }) => CategoryConfigCacheRow(
    id: id ?? this.id,
    version: version.present ? version.value : this.version,
    etag: etag.present ? etag.value : this.etag,
    jsonBody: jsonBody.present ? jsonBody.value : this.jsonBody,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
  );
  CategoryConfigCacheRow copyWithCompanion(CategoryConfigCacheCompanion data) {
    return CategoryConfigCacheRow(
      id: data.id.present ? data.id.value : this.id,
      version: data.version.present ? data.version.value : this.version,
      etag: data.etag.present ? data.etag.value : this.etag,
      jsonBody: data.jsonBody.present ? data.jsonBody.value : this.jsonBody,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryConfigCacheRow(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('etag: $etag, ')
          ..write('jsonBody: $jsonBody, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, version, etag, jsonBody, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryConfigCacheRow &&
          other.id == this.id &&
          other.version == this.version &&
          other.etag == this.etag &&
          other.jsonBody == this.jsonBody &&
          other.updatedAt == this.updatedAt);
}

class CategoryConfigCacheCompanion
    extends UpdateCompanion<CategoryConfigCacheRow> {
  final Value<int> id;
  final Value<String?> version;
  final Value<String?> etag;
  final Value<String?> jsonBody;
  final Value<DateTime?> updatedAt;
  const CategoryConfigCacheCompanion({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.etag = const Value.absent(),
    this.jsonBody = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  CategoryConfigCacheCompanion.insert({
    this.id = const Value.absent(),
    this.version = const Value.absent(),
    this.etag = const Value.absent(),
    this.jsonBody = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<CategoryConfigCacheRow> custom({
    Expression<int>? id,
    Expression<String>? version,
    Expression<String>? etag,
    Expression<String>? jsonBody,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (version != null) 'version': version,
      if (etag != null) 'etag': etag,
      if (jsonBody != null) 'json_body': jsonBody,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  CategoryConfigCacheCompanion copyWith({
    Value<int>? id,
    Value<String?>? version,
    Value<String?>? etag,
    Value<String?>? jsonBody,
    Value<DateTime?>? updatedAt,
  }) {
    return CategoryConfigCacheCompanion(
      id: id ?? this.id,
      version: version ?? this.version,
      etag: etag ?? this.etag,
      jsonBody: jsonBody ?? this.jsonBody,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (jsonBody.present) {
      map['json_body'] = Variable<String>(jsonBody.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryConfigCacheCompanion(')
          ..write('id: $id, ')
          ..write('version: $version, ')
          ..write('etag: $etag, ')
          ..write('jsonBody: $jsonBody, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OutboxTransactionsTable outboxTransactions =
      $OutboxTransactionsTable(this);
  late final $OutboxArtifactsTable outboxArtifacts = $OutboxArtifactsTable(
    this,
  );
  late final $OutboxLineItemsTable outboxLineItems = $OutboxLineItemsTable(
    this,
  );
  late final $CategoryConfigCacheTable categoryConfigCache =
      $CategoryConfigCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    outboxTransactions,
    outboxArtifacts,
    outboxLineItems,
    categoryConfigCache,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'outbox_transactions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox_artifacts', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'outbox_transactions',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('outbox_line_items', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$OutboxTransactionsTableCreateCompanionBuilder =
    OutboxTransactionsCompanion Function({
      required String id,
      required String userId,
      Value<DateTime> createdAt,
      Value<DateTime> occurredAt,
      Value<double?> amountMyr,
      Value<String?> amountSource,
      Value<bool> needsAmount,
      Value<String?> merchantRaw,
      Value<String?> merchantNormalized,
      Value<String?> categoryGuess,
      Value<String?> categoryUser,
      Value<double?> categoryConfidence,
      Value<String?> impactUser,
      Value<String> placeStatus,
      Value<String?> placeGooglePlaceId,
      Value<String?> placeName,
      Value<double?> placeLat,
      Value<double?> placeLng,
      Value<double?> placeConfidence,
      Value<double?> shareLocationLat,
      Value<double?> shareLocationLng,
      Value<DateTime?> shareLocationCapturedAt,
      Value<double?> ocrConfidence,
      Value<String?> rawOcrText,
      Value<double?> ocrServiceConfidence,
      Value<double?> lineItemsConfidence,
      Value<String?> parseFailureReason,
      Value<String> pipelineStatus,
      Value<String> syncStatus,
      Value<String?> lastError,
      Value<int> retryCount,
      Value<DateTime?> ritualledAt,
      Value<String?> merchantCandidatesJson,
      Value<String?> ocrHeaderText,
      Value<int> rowid,
    });
typedef $$OutboxTransactionsTableUpdateCompanionBuilder =
    OutboxTransactionsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<DateTime> createdAt,
      Value<DateTime> occurredAt,
      Value<double?> amountMyr,
      Value<String?> amountSource,
      Value<bool> needsAmount,
      Value<String?> merchantRaw,
      Value<String?> merchantNormalized,
      Value<String?> categoryGuess,
      Value<String?> categoryUser,
      Value<double?> categoryConfidence,
      Value<String?> impactUser,
      Value<String> placeStatus,
      Value<String?> placeGooglePlaceId,
      Value<String?> placeName,
      Value<double?> placeLat,
      Value<double?> placeLng,
      Value<double?> placeConfidence,
      Value<double?> shareLocationLat,
      Value<double?> shareLocationLng,
      Value<DateTime?> shareLocationCapturedAt,
      Value<double?> ocrConfidence,
      Value<String?> rawOcrText,
      Value<double?> ocrServiceConfidence,
      Value<double?> lineItemsConfidence,
      Value<String?> parseFailureReason,
      Value<String> pipelineStatus,
      Value<String> syncStatus,
      Value<String?> lastError,
      Value<int> retryCount,
      Value<DateTime?> ritualledAt,
      Value<String?> merchantCandidatesJson,
      Value<String?> ocrHeaderText,
      Value<int> rowid,
    });

final class $$OutboxTransactionsTableReferences
    extends
        BaseReferences<
          _$AppDatabase,
          $OutboxTransactionsTable,
          OutboxTransaction
        > {
  $$OutboxTransactionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$OutboxArtifactsTable, List<OutboxArtifact>>
  _outboxArtifactsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.outboxArtifacts,
    aliasName: $_aliasNameGenerator(
      db.outboxTransactions.id,
      db.outboxArtifacts.transactionId,
    ),
  );

  $$OutboxArtifactsTableProcessedTableManager get outboxArtifactsRefs {
    final manager = $$OutboxArtifactsTableTableManager(
      $_db,
      $_db.outboxArtifacts,
    ).filter((f) => f.transactionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outboxArtifactsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$OutboxLineItemsTable, List<OutboxLineItem>>
  _outboxLineItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.outboxLineItems,
    aliasName: $_aliasNameGenerator(
      db.outboxTransactions.id,
      db.outboxLineItems.transactionId,
    ),
  );

  $$OutboxLineItemsTableProcessedTableManager get outboxLineItemsRefs {
    final manager = $$OutboxLineItemsTableTableManager(
      $_db,
      $_db.outboxLineItems,
    ).filter((f) => f.transactionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _outboxLineItemsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$OutboxTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTransactionsTable> {
  $$OutboxTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amountMyr => $composableBuilder(
    column: $table.amountMyr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get amountSource => $composableBuilder(
    column: $table.amountSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsAmount => $composableBuilder(
    column: $table.needsAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get merchantRaw => $composableBuilder(
    column: $table.merchantRaw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get merchantNormalized => $composableBuilder(
    column: $table.merchantNormalized,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryGuess => $composableBuilder(
    column: $table.categoryGuess,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryUser => $composableBuilder(
    column: $table.categoryUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get categoryConfidence => $composableBuilder(
    column: $table.categoryConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get impactUser => $composableBuilder(
    column: $table.impactUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeStatus => $composableBuilder(
    column: $table.placeStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeGooglePlaceId => $composableBuilder(
    column: $table.placeGooglePlaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get placeLat => $composableBuilder(
    column: $table.placeLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get placeLng => $composableBuilder(
    column: $table.placeLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get placeConfidence => $composableBuilder(
    column: $table.placeConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get shareLocationLat => $composableBuilder(
    column: $table.shareLocationLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get shareLocationLng => $composableBuilder(
    column: $table.shareLocationLng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get shareLocationCapturedAt => $composableBuilder(
    column: $table.shareLocationCapturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawOcrText => $composableBuilder(
    column: $table.rawOcrText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get ocrServiceConfidence => $composableBuilder(
    column: $table.ocrServiceConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lineItemsConfidence => $composableBuilder(
    column: $table.lineItemsConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parseFailureReason => $composableBuilder(
    column: $table.parseFailureReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pipelineStatus => $composableBuilder(
    column: $table.pipelineStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get ritualledAt => $composableBuilder(
    column: $table.ritualledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get merchantCandidatesJson => $composableBuilder(
    column: $table.merchantCandidatesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ocrHeaderText => $composableBuilder(
    column: $table.ocrHeaderText,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> outboxArtifactsRefs(
    Expression<bool> Function($$OutboxArtifactsTableFilterComposer f) f,
  ) {
    final $$OutboxArtifactsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxArtifacts,
      getReferencedColumn: (t) => t.transactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxArtifactsTableFilterComposer(
            $db: $db,
            $table: $db.outboxArtifacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> outboxLineItemsRefs(
    Expression<bool> Function($$OutboxLineItemsTableFilterComposer f) f,
  ) {
    final $$OutboxLineItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxLineItems,
      getReferencedColumn: (t) => t.transactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxLineItemsTableFilterComposer(
            $db: $db,
            $table: $db.outboxLineItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OutboxTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTransactionsTable> {
  $$OutboxTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amountMyr => $composableBuilder(
    column: $table.amountMyr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get amountSource => $composableBuilder(
    column: $table.amountSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsAmount => $composableBuilder(
    column: $table.needsAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get merchantRaw => $composableBuilder(
    column: $table.merchantRaw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get merchantNormalized => $composableBuilder(
    column: $table.merchantNormalized,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryGuess => $composableBuilder(
    column: $table.categoryGuess,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryUser => $composableBuilder(
    column: $table.categoryUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get categoryConfidence => $composableBuilder(
    column: $table.categoryConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get impactUser => $composableBuilder(
    column: $table.impactUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeStatus => $composableBuilder(
    column: $table.placeStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeGooglePlaceId => $composableBuilder(
    column: $table.placeGooglePlaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get placeLat => $composableBuilder(
    column: $table.placeLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get placeLng => $composableBuilder(
    column: $table.placeLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get placeConfidence => $composableBuilder(
    column: $table.placeConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get shareLocationLat => $composableBuilder(
    column: $table.shareLocationLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get shareLocationLng => $composableBuilder(
    column: $table.shareLocationLng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get shareLocationCapturedAt => $composableBuilder(
    column: $table.shareLocationCapturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawOcrText => $composableBuilder(
    column: $table.rawOcrText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get ocrServiceConfidence => $composableBuilder(
    column: $table.ocrServiceConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lineItemsConfidence => $composableBuilder(
    column: $table.lineItemsConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parseFailureReason => $composableBuilder(
    column: $table.parseFailureReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pipelineStatus => $composableBuilder(
    column: $table.pipelineStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get ritualledAt => $composableBuilder(
    column: $table.ritualledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get merchantCandidatesJson => $composableBuilder(
    column: $table.merchantCandidatesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ocrHeaderText => $composableBuilder(
    column: $table.ocrHeaderText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTransactionsTable> {
  $$OutboxTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get amountMyr =>
      $composableBuilder(column: $table.amountMyr, builder: (column) => column);

  GeneratedColumn<String> get amountSource => $composableBuilder(
    column: $table.amountSource,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsAmount => $composableBuilder(
    column: $table.needsAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get merchantRaw => $composableBuilder(
    column: $table.merchantRaw,
    builder: (column) => column,
  );

  GeneratedColumn<String> get merchantNormalized => $composableBuilder(
    column: $table.merchantNormalized,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryGuess => $composableBuilder(
    column: $table.categoryGuess,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoryUser => $composableBuilder(
    column: $table.categoryUser,
    builder: (column) => column,
  );

  GeneratedColumn<double> get categoryConfidence => $composableBuilder(
    column: $table.categoryConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get impactUser => $composableBuilder(
    column: $table.impactUser,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeStatus => $composableBuilder(
    column: $table.placeStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeGooglePlaceId => $composableBuilder(
    column: $table.placeGooglePlaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeName =>
      $composableBuilder(column: $table.placeName, builder: (column) => column);

  GeneratedColumn<double> get placeLat =>
      $composableBuilder(column: $table.placeLat, builder: (column) => column);

  GeneratedColumn<double> get placeLng =>
      $composableBuilder(column: $table.placeLng, builder: (column) => column);

  GeneratedColumn<double> get placeConfidence => $composableBuilder(
    column: $table.placeConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<double> get shareLocationLat => $composableBuilder(
    column: $table.shareLocationLat,
    builder: (column) => column,
  );

  GeneratedColumn<double> get shareLocationLng => $composableBuilder(
    column: $table.shareLocationLng,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get shareLocationCapturedAt => $composableBuilder(
    column: $table.shareLocationCapturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ocrConfidence => $composableBuilder(
    column: $table.ocrConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawOcrText => $composableBuilder(
    column: $table.rawOcrText,
    builder: (column) => column,
  );

  GeneratedColumn<double> get ocrServiceConfidence => $composableBuilder(
    column: $table.ocrServiceConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<double> get lineItemsConfidence => $composableBuilder(
    column: $table.lineItemsConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parseFailureReason => $composableBuilder(
    column: $table.parseFailureReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pipelineStatus => $composableBuilder(
    column: $table.pipelineStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get ritualledAt => $composableBuilder(
    column: $table.ritualledAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get merchantCandidatesJson => $composableBuilder(
    column: $table.merchantCandidatesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ocrHeaderText => $composableBuilder(
    column: $table.ocrHeaderText,
    builder: (column) => column,
  );

  Expression<T> outboxArtifactsRefs<T extends Object>(
    Expression<T> Function($$OutboxArtifactsTableAnnotationComposer a) f,
  ) {
    final $$OutboxArtifactsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxArtifacts,
      getReferencedColumn: (t) => t.transactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxArtifactsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxArtifacts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> outboxLineItemsRefs<T extends Object>(
    Expression<T> Function($$OutboxLineItemsTableAnnotationComposer a) f,
  ) {
    final $$OutboxLineItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.outboxLineItems,
      getReferencedColumn: (t) => t.transactionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxLineItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.outboxLineItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$OutboxTransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTransactionsTable,
          OutboxTransaction,
          $$OutboxTransactionsTableFilterComposer,
          $$OutboxTransactionsTableOrderingComposer,
          $$OutboxTransactionsTableAnnotationComposer,
          $$OutboxTransactionsTableCreateCompanionBuilder,
          $$OutboxTransactionsTableUpdateCompanionBuilder,
          (OutboxTransaction, $$OutboxTransactionsTableReferences),
          OutboxTransaction,
          PrefetchHooks Function({
            bool outboxArtifactsRefs,
            bool outboxLineItemsRefs,
          })
        > {
  $$OutboxTransactionsTableTableManager(
    _$AppDatabase db,
    $OutboxTransactionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTransactionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<double?> amountMyr = const Value.absent(),
                Value<String?> amountSource = const Value.absent(),
                Value<bool> needsAmount = const Value.absent(),
                Value<String?> merchantRaw = const Value.absent(),
                Value<String?> merchantNormalized = const Value.absent(),
                Value<String?> categoryGuess = const Value.absent(),
                Value<String?> categoryUser = const Value.absent(),
                Value<double?> categoryConfidence = const Value.absent(),
                Value<String?> impactUser = const Value.absent(),
                Value<String> placeStatus = const Value.absent(),
                Value<String?> placeGooglePlaceId = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<double?> placeLat = const Value.absent(),
                Value<double?> placeLng = const Value.absent(),
                Value<double?> placeConfidence = const Value.absent(),
                Value<double?> shareLocationLat = const Value.absent(),
                Value<double?> shareLocationLng = const Value.absent(),
                Value<DateTime?> shareLocationCapturedAt = const Value.absent(),
                Value<double?> ocrConfidence = const Value.absent(),
                Value<String?> rawOcrText = const Value.absent(),
                Value<double?> ocrServiceConfidence = const Value.absent(),
                Value<double?> lineItemsConfidence = const Value.absent(),
                Value<String?> parseFailureReason = const Value.absent(),
                Value<String> pipelineStatus = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> ritualledAt = const Value.absent(),
                Value<String?> merchantCandidatesJson = const Value.absent(),
                Value<String?> ocrHeaderText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxTransactionsCompanion(
                id: id,
                userId: userId,
                createdAt: createdAt,
                occurredAt: occurredAt,
                amountMyr: amountMyr,
                amountSource: amountSource,
                needsAmount: needsAmount,
                merchantRaw: merchantRaw,
                merchantNormalized: merchantNormalized,
                categoryGuess: categoryGuess,
                categoryUser: categoryUser,
                categoryConfidence: categoryConfidence,
                impactUser: impactUser,
                placeStatus: placeStatus,
                placeGooglePlaceId: placeGooglePlaceId,
                placeName: placeName,
                placeLat: placeLat,
                placeLng: placeLng,
                placeConfidence: placeConfidence,
                shareLocationLat: shareLocationLat,
                shareLocationLng: shareLocationLng,
                shareLocationCapturedAt: shareLocationCapturedAt,
                ocrConfidence: ocrConfidence,
                rawOcrText: rawOcrText,
                ocrServiceConfidence: ocrServiceConfidence,
                lineItemsConfidence: lineItemsConfidence,
                parseFailureReason: parseFailureReason,
                pipelineStatus: pipelineStatus,
                syncStatus: syncStatus,
                lastError: lastError,
                retryCount: retryCount,
                ritualledAt: ritualledAt,
                merchantCandidatesJson: merchantCandidatesJson,
                ocrHeaderText: ocrHeaderText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<double?> amountMyr = const Value.absent(),
                Value<String?> amountSource = const Value.absent(),
                Value<bool> needsAmount = const Value.absent(),
                Value<String?> merchantRaw = const Value.absent(),
                Value<String?> merchantNormalized = const Value.absent(),
                Value<String?> categoryGuess = const Value.absent(),
                Value<String?> categoryUser = const Value.absent(),
                Value<double?> categoryConfidence = const Value.absent(),
                Value<String?> impactUser = const Value.absent(),
                Value<String> placeStatus = const Value.absent(),
                Value<String?> placeGooglePlaceId = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<double?> placeLat = const Value.absent(),
                Value<double?> placeLng = const Value.absent(),
                Value<double?> placeConfidence = const Value.absent(),
                Value<double?> shareLocationLat = const Value.absent(),
                Value<double?> shareLocationLng = const Value.absent(),
                Value<DateTime?> shareLocationCapturedAt = const Value.absent(),
                Value<double?> ocrConfidence = const Value.absent(),
                Value<String?> rawOcrText = const Value.absent(),
                Value<double?> ocrServiceConfidence = const Value.absent(),
                Value<double?> lineItemsConfidence = const Value.absent(),
                Value<String?> parseFailureReason = const Value.absent(),
                Value<String> pipelineStatus = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime?> ritualledAt = const Value.absent(),
                Value<String?> merchantCandidatesJson = const Value.absent(),
                Value<String?> ocrHeaderText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxTransactionsCompanion.insert(
                id: id,
                userId: userId,
                createdAt: createdAt,
                occurredAt: occurredAt,
                amountMyr: amountMyr,
                amountSource: amountSource,
                needsAmount: needsAmount,
                merchantRaw: merchantRaw,
                merchantNormalized: merchantNormalized,
                categoryGuess: categoryGuess,
                categoryUser: categoryUser,
                categoryConfidence: categoryConfidence,
                impactUser: impactUser,
                placeStatus: placeStatus,
                placeGooglePlaceId: placeGooglePlaceId,
                placeName: placeName,
                placeLat: placeLat,
                placeLng: placeLng,
                placeConfidence: placeConfidence,
                shareLocationLat: shareLocationLat,
                shareLocationLng: shareLocationLng,
                shareLocationCapturedAt: shareLocationCapturedAt,
                ocrConfidence: ocrConfidence,
                rawOcrText: rawOcrText,
                ocrServiceConfidence: ocrServiceConfidence,
                lineItemsConfidence: lineItemsConfidence,
                parseFailureReason: parseFailureReason,
                pipelineStatus: pipelineStatus,
                syncStatus: syncStatus,
                lastError: lastError,
                retryCount: retryCount,
                ritualledAt: ritualledAt,
                merchantCandidatesJson: merchantCandidatesJson,
                ocrHeaderText: ocrHeaderText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxTransactionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({outboxArtifactsRefs = false, outboxLineItemsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (outboxArtifactsRefs) db.outboxArtifacts,
                    if (outboxLineItemsRefs) db.outboxLineItems,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (outboxArtifactsRefs)
                        await $_getPrefetchedData<
                          OutboxTransaction,
                          $OutboxTransactionsTable,
                          OutboxArtifact
                        >(
                          currentTable: table,
                          referencedTable: $$OutboxTransactionsTableReferences
                              ._outboxArtifactsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$OutboxTransactionsTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxArtifactsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.transactionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (outboxLineItemsRefs)
                        await $_getPrefetchedData<
                          OutboxTransaction,
                          $OutboxTransactionsTable,
                          OutboxLineItem
                        >(
                          currentTable: table,
                          referencedTable: $$OutboxTransactionsTableReferences
                              ._outboxLineItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$OutboxTransactionsTableReferences(
                                db,
                                table,
                                p0,
                              ).outboxLineItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.transactionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$OutboxTransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTransactionsTable,
      OutboxTransaction,
      $$OutboxTransactionsTableFilterComposer,
      $$OutboxTransactionsTableOrderingComposer,
      $$OutboxTransactionsTableAnnotationComposer,
      $$OutboxTransactionsTableCreateCompanionBuilder,
      $$OutboxTransactionsTableUpdateCompanionBuilder,
      (OutboxTransaction, $$OutboxTransactionsTableReferences),
      OutboxTransaction,
      PrefetchHooks Function({
        bool outboxArtifactsRefs,
        bool outboxLineItemsRefs,
      })
    >;
typedef $$OutboxArtifactsTableCreateCompanionBuilder =
    OutboxArtifactsCompanion Function({
      required String id,
      required String userId,
      required String transactionId,
      Value<String?> storagePath,
      required String mimeType,
      required String localFilePath,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$OutboxArtifactsTableUpdateCompanionBuilder =
    OutboxArtifactsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> transactionId,
      Value<String?> storagePath,
      Value<String> mimeType,
      Value<String> localFilePath,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$OutboxArtifactsTableReferences
    extends
        BaseReferences<_$AppDatabase, $OutboxArtifactsTable, OutboxArtifact> {
  $$OutboxArtifactsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OutboxTransactionsTable _transactionIdTable(_$AppDatabase db) =>
      db.outboxTransactions.createAlias(
        $_aliasNameGenerator(
          db.outboxArtifacts.transactionId,
          db.outboxTransactions.id,
        ),
      );

  $$OutboxTransactionsTableProcessedTableManager get transactionId {
    final $_column = $_itemColumn<String>('transaction_id')!;

    final manager = $$OutboxTransactionsTableTableManager(
      $_db,
      $_db.outboxTransactions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_transactionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxArtifactsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxArtifactsTable> {
  $$OutboxArtifactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$OutboxTransactionsTableFilterComposer get transactionId {
    final $$OutboxTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.outboxTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.outboxTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxArtifactsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxArtifactsTable> {
  $$OutboxArtifactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$OutboxTransactionsTableOrderingComposer get transactionId {
    final $$OutboxTransactionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.outboxTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxTransactionsTableOrderingComposer(
            $db: $db,
            $table: $db.outboxTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxArtifactsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxArtifactsTable> {
  $$OutboxArtifactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get localFilePath => $composableBuilder(
    column: $table.localFilePath,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$OutboxTransactionsTableAnnotationComposer get transactionId {
    final $$OutboxTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.transactionId,
          referencedTable: $db.outboxTransactions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutboxTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.outboxTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OutboxArtifactsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxArtifactsTable,
          OutboxArtifact,
          $$OutboxArtifactsTableFilterComposer,
          $$OutboxArtifactsTableOrderingComposer,
          $$OutboxArtifactsTableAnnotationComposer,
          $$OutboxArtifactsTableCreateCompanionBuilder,
          $$OutboxArtifactsTableUpdateCompanionBuilder,
          (OutboxArtifact, $$OutboxArtifactsTableReferences),
          OutboxArtifact,
          PrefetchHooks Function({bool transactionId})
        > {
  $$OutboxArtifactsTableTableManager(
    _$AppDatabase db,
    $OutboxArtifactsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxArtifactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxArtifactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxArtifactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> transactionId = const Value.absent(),
                Value<String?> storagePath = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<String> localFilePath = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxArtifactsCompanion(
                id: id,
                userId: userId,
                transactionId: transactionId,
                storagePath: storagePath,
                mimeType: mimeType,
                localFilePath: localFilePath,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String transactionId,
                Value<String?> storagePath = const Value.absent(),
                required String mimeType,
                required String localFilePath,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxArtifactsCompanion.insert(
                id: id,
                userId: userId,
                transactionId: transactionId,
                storagePath: storagePath,
                mimeType: mimeType,
                localFilePath: localFilePath,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxArtifactsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({transactionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (transactionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.transactionId,
                                referencedTable:
                                    $$OutboxArtifactsTableReferences
                                        ._transactionIdTable(db),
                                referencedColumn:
                                    $$OutboxArtifactsTableReferences
                                        ._transactionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutboxArtifactsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxArtifactsTable,
      OutboxArtifact,
      $$OutboxArtifactsTableFilterComposer,
      $$OutboxArtifactsTableOrderingComposer,
      $$OutboxArtifactsTableAnnotationComposer,
      $$OutboxArtifactsTableCreateCompanionBuilder,
      $$OutboxArtifactsTableUpdateCompanionBuilder,
      (OutboxArtifact, $$OutboxArtifactsTableReferences),
      OutboxArtifact,
      PrefetchHooks Function({bool transactionId})
    >;
typedef $$OutboxLineItemsTableCreateCompanionBuilder =
    OutboxLineItemsCompanion Function({
      required String id,
      required String userId,
      required String transactionId,
      required String name,
      required double priceMyr,
      Value<int?> quantity,
      Value<double?> confidence,
      required int sortOrder,
      Value<int> rowid,
    });
typedef $$OutboxLineItemsTableUpdateCompanionBuilder =
    OutboxLineItemsCompanion Function({
      Value<String> id,
      Value<String> userId,
      Value<String> transactionId,
      Value<String> name,
      Value<double> priceMyr,
      Value<int?> quantity,
      Value<double?> confidence,
      Value<int> sortOrder,
      Value<int> rowid,
    });

final class $$OutboxLineItemsTableReferences
    extends
        BaseReferences<_$AppDatabase, $OutboxLineItemsTable, OutboxLineItem> {
  $$OutboxLineItemsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $OutboxTransactionsTable _transactionIdTable(_$AppDatabase db) =>
      db.outboxTransactions.createAlias(
        $_aliasNameGenerator(
          db.outboxLineItems.transactionId,
          db.outboxTransactions.id,
        ),
      );

  $$OutboxTransactionsTableProcessedTableManager get transactionId {
    final $_column = $_itemColumn<String>('transaction_id')!;

    final manager = $$OutboxTransactionsTableTableManager(
      $_db,
      $_db.outboxTransactions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_transactionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$OutboxLineItemsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxLineItemsTable> {
  $$OutboxLineItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get priceMyr => $composableBuilder(
    column: $table.priceMyr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  $$OutboxTransactionsTableFilterComposer get transactionId {
    final $$OutboxTransactionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.outboxTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxTransactionsTableFilterComposer(
            $db: $db,
            $table: $db.outboxTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxLineItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxLineItemsTable> {
  $$OutboxLineItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get priceMyr => $composableBuilder(
    column: $table.priceMyr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quantity => $composableBuilder(
    column: $table.quantity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  $$OutboxTransactionsTableOrderingComposer get transactionId {
    final $$OutboxTransactionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.transactionId,
      referencedTable: $db.outboxTransactions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$OutboxTransactionsTableOrderingComposer(
            $db: $db,
            $table: $db.outboxTransactions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$OutboxLineItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxLineItemsTable> {
  $$OutboxLineItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get priceMyr =>
      $composableBuilder(column: $table.priceMyr, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  $$OutboxTransactionsTableAnnotationComposer get transactionId {
    final $$OutboxTransactionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.transactionId,
          referencedTable: $db.outboxTransactions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$OutboxTransactionsTableAnnotationComposer(
                $db: $db,
                $table: $db.outboxTransactions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$OutboxLineItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxLineItemsTable,
          OutboxLineItem,
          $$OutboxLineItemsTableFilterComposer,
          $$OutboxLineItemsTableOrderingComposer,
          $$OutboxLineItemsTableAnnotationComposer,
          $$OutboxLineItemsTableCreateCompanionBuilder,
          $$OutboxLineItemsTableUpdateCompanionBuilder,
          (OutboxLineItem, $$OutboxLineItemsTableReferences),
          OutboxLineItem,
          PrefetchHooks Function({bool transactionId})
        > {
  $$OutboxLineItemsTableTableManager(
    _$AppDatabase db,
    $OutboxLineItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxLineItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxLineItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxLineItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> transactionId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> priceMyr = const Value.absent(),
                Value<int?> quantity = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxLineItemsCompanion(
                id: id,
                userId: userId,
                transactionId: transactionId,
                name: name,
                priceMyr: priceMyr,
                quantity: quantity,
                confidence: confidence,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String userId,
                required String transactionId,
                required String name,
                required double priceMyr,
                Value<int?> quantity = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                required int sortOrder,
                Value<int> rowid = const Value.absent(),
              }) => OutboxLineItemsCompanion.insert(
                id: id,
                userId: userId,
                transactionId: transactionId,
                name: name,
                priceMyr: priceMyr,
                quantity: quantity,
                confidence: confidence,
                sortOrder: sortOrder,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$OutboxLineItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({transactionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (transactionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.transactionId,
                                referencedTable:
                                    $$OutboxLineItemsTableReferences
                                        ._transactionIdTable(db),
                                referencedColumn:
                                    $$OutboxLineItemsTableReferences
                                        ._transactionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$OutboxLineItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxLineItemsTable,
      OutboxLineItem,
      $$OutboxLineItemsTableFilterComposer,
      $$OutboxLineItemsTableOrderingComposer,
      $$OutboxLineItemsTableAnnotationComposer,
      $$OutboxLineItemsTableCreateCompanionBuilder,
      $$OutboxLineItemsTableUpdateCompanionBuilder,
      (OutboxLineItem, $$OutboxLineItemsTableReferences),
      OutboxLineItem,
      PrefetchHooks Function({bool transactionId})
    >;
typedef $$CategoryConfigCacheTableCreateCompanionBuilder =
    CategoryConfigCacheCompanion Function({
      Value<int> id,
      Value<String?> version,
      Value<String?> etag,
      Value<String?> jsonBody,
      Value<DateTime?> updatedAt,
    });
typedef $$CategoryConfigCacheTableUpdateCompanionBuilder =
    CategoryConfigCacheCompanion Function({
      Value<int> id,
      Value<String?> version,
      Value<String?> etag,
      Value<String?> jsonBody,
      Value<DateTime?> updatedAt,
    });

class $$CategoryConfigCacheTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryConfigCacheTable> {
  $$CategoryConfigCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get jsonBody => $composableBuilder(
    column: $table.jsonBody,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoryConfigCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryConfigCacheTable> {
  $$CategoryConfigCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get jsonBody => $composableBuilder(
    column: $table.jsonBody,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoryConfigCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryConfigCacheTable> {
  $$CategoryConfigCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<String> get jsonBody =>
      $composableBuilder(column: $table.jsonBody, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CategoryConfigCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoryConfigCacheTable,
          CategoryConfigCacheRow,
          $$CategoryConfigCacheTableFilterComposer,
          $$CategoryConfigCacheTableOrderingComposer,
          $$CategoryConfigCacheTableAnnotationComposer,
          $$CategoryConfigCacheTableCreateCompanionBuilder,
          $$CategoryConfigCacheTableUpdateCompanionBuilder,
          (
            CategoryConfigCacheRow,
            BaseReferences<
              _$AppDatabase,
              $CategoryConfigCacheTable,
              CategoryConfigCacheRow
            >,
          ),
          CategoryConfigCacheRow,
          PrefetchHooks Function()
        > {
  $$CategoryConfigCacheTableTableManager(
    _$AppDatabase db,
    $CategoryConfigCacheTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryConfigCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryConfigCacheTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CategoryConfigCacheTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> version = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> jsonBody = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => CategoryConfigCacheCompanion(
                id: id,
                version: version,
                etag: etag,
                jsonBody: jsonBody,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> version = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<String?> jsonBody = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
              }) => CategoryConfigCacheCompanion.insert(
                id: id,
                version: version,
                etag: etag,
                jsonBody: jsonBody,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoryConfigCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoryConfigCacheTable,
      CategoryConfigCacheRow,
      $$CategoryConfigCacheTableFilterComposer,
      $$CategoryConfigCacheTableOrderingComposer,
      $$CategoryConfigCacheTableAnnotationComposer,
      $$CategoryConfigCacheTableCreateCompanionBuilder,
      $$CategoryConfigCacheTableUpdateCompanionBuilder,
      (
        CategoryConfigCacheRow,
        BaseReferences<
          _$AppDatabase,
          $CategoryConfigCacheTable,
          CategoryConfigCacheRow
        >,
      ),
      CategoryConfigCacheRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OutboxTransactionsTableTableManager get outboxTransactions =>
      $$OutboxTransactionsTableTableManager(_db, _db.outboxTransactions);
  $$OutboxArtifactsTableTableManager get outboxArtifacts =>
      $$OutboxArtifactsTableTableManager(_db, _db.outboxArtifacts);
  $$OutboxLineItemsTableTableManager get outboxLineItems =>
      $$OutboxLineItemsTableTableManager(_db, _db.outboxLineItems);
  $$CategoryConfigCacheTableTableManager get categoryConfigCache =>
      $$CategoryConfigCacheTableTableManager(_db, _db.categoryConfigCache);
}
