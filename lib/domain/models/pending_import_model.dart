/// In-memory representation of a locally-saved pending receipt, decoupled from
/// the Drift [PendingImport] data class so platform-neutral code (home screen
/// banner, pending imports screen) can use it on web without pulling in SQLite.
class PendingImportModel {
  const PendingImportModel({
    required this.id,
    required this.userId,
    required this.localFilePath,
    required this.mimeType,
    required this.status,
    required this.createdAt,
    this.sourceApp,
    this.note,
    this.venueLabel,
  });

  final String id;
  final String userId;
  final String localFilePath;
  final String mimeType;

  /// 'local' | 'processing' | 'failed'
  final String status;

  final DateTime createdAt;
  final String? sourceApp;

  /// Freeform note attached via the post-share notification's inline reply
  /// (or later, in-app) before this import becomes a confirmed transaction.
  final String? note;

  /// Best-effort nearby-venue name resolved from a share-time GPS fix — a
  /// memory aid only. Null until resolved, or permanently if location was
  /// unavailable/denied/couldn't be resolved to a nearby place.
  final String? venueLabel;

  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing';
}
