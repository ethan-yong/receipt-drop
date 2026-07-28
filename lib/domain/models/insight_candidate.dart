/// Closed vocabulary of insight agent types. Must stay in sync with the
/// curator Edge Function whitelist and ocr-api `/curate-insights` validator.
const kInsightTypes = {
  'spending_spike',
  'category_shift',
  'habit',
  'streak',
  'forecast',
};

/// Structured fact emitted by an on-device detector. Never includes raw OCR
/// text or full transaction lists — only the aggregated facts the curator
/// needs to rewrite into a friendly sentence.
class InsightCandidate {
  const InsightCandidate({
    required this.type,
    required this.factKey,
    required this.facts,
    required this.severity,
    this.templateHint,
  });

  /// One of [kInsightTypes].
  final String type;

  /// Stable dedup key for this underlying fact (e.g. `spike:saturday:2026-07-26`).
  /// Used to suppress resurfacing after dismiss or within consecutive cycles.
  final String factKey;

  /// Concrete numeric/categorical facts justifying the candidate.
  /// Keys are free-form but should be short (category, multiplier, placeName…).
  final Map<String, Object?> facts;

  /// Locally-computed novelty/severity score in 0..1 — higher ranks first.
  final double severity;

  /// Optional human-readable hint the curator may paraphrase (never invent beyond).
  final String? templateHint;

  Map<String, dynamic> toJson() => {
        'type': type,
        'fact_key': factKey,
        'facts': facts,
        'severity': severity,
        if (templateHint != null) 'template_hint': templateHint,
      };

  static InsightCandidate? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    final factKey = json['fact_key'] ?? json['factKey'];
    final factsRaw = json['facts'];
    final severity = json['severity'];
    if (type is! String || !kInsightTypes.contains(type)) return null;
    if (factKey is! String || factKey.isEmpty) return null;
    if (factsRaw is! Map) return null;
    final sev = severity is num ? severity.toDouble() : 0.0;
    return InsightCandidate(
      type: type,
      factKey: factKey,
      facts: Map<String, Object?>.from(factsRaw),
      severity: sev.clamp(0.0, 1.0),
      templateHint: json['template_hint'] is String
          ? json['template_hint'] as String
          : json['templateHint'] is String
              ? json['templateHint'] as String
              : null,
    );
  }
}

/// A curated, user-facing insight ready for display / persistence.
class CuratedInsight {
  const CuratedInsight({
    required this.id,
    required this.type,
    required this.factKey,
    required this.body,
    required this.rank,
    required this.createdAt,
    this.dismissed = false,
  });

  final String id;
  final String type;
  final String factKey;
  final String body;
  final int rank;
  final DateTime createdAt;
  final bool dismissed;

  CuratedInsight copyWith({bool? dismissed}) => CuratedInsight(
        id: id,
        type: type,
        factKey: factKey,
        body: body,
        rank: rank,
        createdAt: createdAt,
        dismissed: dismissed ?? this.dismissed,
      );

  static CuratedInsight? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final type = json['type'];
    final factKey = json['fact_key'] ?? json['factKey'];
    final rank = json['rank'];
    final createdAt = json['created_at'] ?? json['createdAt'];
    if (id is! String || id.isEmpty) return null;
    if (type is! String || !kInsightTypes.contains(type)) return null;
    if (factKey is! String || factKey.isEmpty) return null;
    final bodyRaw = json['body'];
    final title = json['title'];
    final description = json['description'];
    String? body;
    if (bodyRaw is String && bodyRaw.trim().isNotEmpty) {
      body = bodyRaw.trim();
    } else if (description is String && description.trim().isNotEmpty) {
      final desc = description.trim();
      if (title is String && title.trim().isNotEmpty) {
        body = '${title.trim()}. $desc';
      } else {
        body = desc;
      }
    }
    if (body == null || body.isEmpty) return null;
    DateTime? parsed;
    if (createdAt is String) {
      parsed = DateTime.tryParse(createdAt);
    } else if (createdAt is DateTime) {
      parsed = createdAt;
    }
    return CuratedInsight(
      id: id,
      type: type,
      factKey: factKey,
      body: body,
      rank: rank is num ? rank.toInt() : 0,
      createdAt: parsed ?? DateTime.now(),
      dismissed: json['dismissed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'fact_key': factKey,
        'body': body,
        'rank': rank,
        'created_at': createdAt.toUtc().toIso8601String(),
        'dismissed': dismissed,
      };
}
