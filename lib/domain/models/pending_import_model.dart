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
  });

  final String id;
  final String userId;
  final String localFilePath;
  final String mimeType;

  /// 'local' | 'processing' | 'failed'
  final String status;

  final DateTime createdAt;
  final String? sourceApp;

  bool get isFailed => status == 'failed';
  bool get isProcessing => status == 'processing';
}
