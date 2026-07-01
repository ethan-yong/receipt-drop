import 'dart:typed_data';

/// Persisted receipt bytes + path reference for ingest.
class StoredReceiptFile {
  const StoredReceiptFile({
    required this.localPath,
    required this.mimeType,
    required this.bytes,
  });

  final String localPath;
  final String mimeType;
  final Uint8List bytes;
}
