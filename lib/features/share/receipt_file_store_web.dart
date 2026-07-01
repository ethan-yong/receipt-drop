import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'stored_receipt_file.dart';

Future<StoredReceiptFile> persistReceiptBytes(
  Uint8List bytes,
  String mimeType,
) async {
  final id = const Uuid().v4();
  return StoredReceiptFile(
    localPath: 'web:$id',
    mimeType: mimeType,
    bytes: bytes,
  );
}

Future<void> deleteStoredReceipt(String localPath) async {}
