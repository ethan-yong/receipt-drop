import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/features/share/ocr_pipeline_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final captured = <({String message, Object? error})>[];

  void fakeLogger(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    int level = 0,
  }) {
    captured.add((message: message, error: error));
  }

  setUp(() {
    captured.clear();
    ocrLogger = fakeLogger;
  });

  tearDown(() {
    ocrLogger = fakeLogger;
  });

  test('logs and returns empty string when image OCR fails', () async {
    final result = await runOcrOnReceiptFile(
      filePath: 'nonexistent-receipt.jpg',
      mimeType: 'image/jpeg',
    );

    expect(result, isEmpty);
    expect(captured, isNotEmpty);
    expect(captured.any((c) => c.error != null), isTrue);
  });

  test('logs and returns empty string when PDF extraction fails', () async {
    final result = await runOcrOnReceiptFile(
      filePath: 'nonexistent-receipt.pdf',
      mimeType: 'application/pdf',
    );

    expect(result, isEmpty);
    expect(captured, isNotEmpty);
    expect(captured.any((c) => c.error != null), isTrue);
  });
}
