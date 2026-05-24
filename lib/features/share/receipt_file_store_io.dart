import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'stored_receipt_file.dart';

Future<StoredReceiptFile> persistReceiptBytes(
  Uint8List bytes,
  String mimeType,
) async {
  final dir = await getApplicationDocumentsDirectory();
  final receiptsDir = Directory(p.join(dir.path, 'receipts'));
  if (!await receiptsDir.exists()) {
    await receiptsDir.create(recursive: true);
  }
  final ext = _extensionForMime(mimeType);
  final name = '${const Uuid().v4()}.$ext';
  final dest = File(p.join(receiptsDir.path, name));
  await dest.writeAsBytes(bytes, flush: true);
  return StoredReceiptFile(
    localPath: dest.path,
    mimeType: mimeType,
    bytes: bytes,
  );
}

Future<void> deleteStoredReceipt(String localPath) async {
  try {
    final file = File(localPath);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {}
}

String _extensionForMime(String mimeType) {
  if (mimeType.contains('pdf')) return 'pdf';
  if (mimeType.contains('png')) return 'png';
  if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpg';
  return 'bin';
}
