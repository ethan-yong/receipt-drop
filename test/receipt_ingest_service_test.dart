
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/features/share/receipt_ingest_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '.';
        }
        return null;
      },
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  test('ingestBytes marks needsAmount when OCR finds no amount', () async {
    final bytes = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);

    final draft = await ReceiptIngestService.ingestBytes(
      bytes: bytes,
      mimeType: 'image/png',
    );

    expect(draft.needsAmount, isTrue);
    expect(draft.amountMyr, isNull);
    expect(draft.localFilePath, isNotEmpty);
    expect(draft.thumbnailBytes, isNotNull);

    await ReceiptIngestService.discardDraft(draft);
  });
}
