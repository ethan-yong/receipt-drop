import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:receipt_drop/features/share/ocr_api_client.dart';

void main() {
  test('runOcrApi returns text and confidence on 200', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      if (request.uri.path == '/ocr' && request.method == 'POST') {
        expect(request.headers.value('x-ocr-secret'), 'test-secret');
        expect(request.headers.value('content-type'), 'image/png');
        final body = await request.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        expect(body, isNotEmpty);
        request.response
          ..statusCode = 200
          ..write(jsonEncode({'text': 'TOTAL RM 7.70', 'confidence': 0.99}))
          ..close();
        return;
      }
      request.response
        ..statusCode = 404
        ..close();
    });

    final port = server.port;
    final dir = await Directory.systemTemp.createTemp('ocr_client_test');
    addTearDown(() => dir.delete(recursive: true));
    final image = File('${dir.path}/sample.png');
    await image.writeAsBytes([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);

    final result = await runOcrApi(
      filePath: image.path,
      mimeType: 'image/png',
      ocrUrl: Uri.parse('http://127.0.0.1:$port/ocr'),
      secret: 'test-secret',
      client: http.Client(),
    );

    expect(result, isNotNull);
    expect(result!.text, 'TOTAL RM 7.70');
    expect(result.confidence, closeTo(0.99, 0.001));
  });

  test('runOcrApi returns null on unauthorized', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      request.response
        ..statusCode = 401
        ..write(jsonEncode({'error': 'unauthorized'}))
        ..close();
    });

    final port = server.port;
    final dir = await Directory.systemTemp.createTemp('ocr_client_test');
    addTearDown(() => dir.delete(recursive: true));
    final image = File('${dir.path}/sample.png');
    await image.writeAsBytes([1, 2, 3]);

    final result = await runOcrApi(
      filePath: image.path,
      mimeType: 'image/png',
      ocrUrl: Uri.parse('http://127.0.0.1:$port/ocr'),
      secret: 'wrong',
      client: http.Client(),
    );

    expect(result, isNull);
  });

  test('runOcrApi returns null for unsupported mime types', () async {
    final dir = await Directory.systemTemp.createTemp('ocr_client_test');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File('${dir.path}/sample.pdf');
    await pdf.writeAsBytes([1, 2, 3]);

    final result = await runOcrApi(
      filePath: pdf.path,
      mimeType: 'application/pdf',
      ocrUrl: Uri.parse('http://127.0.0.1:9/ocr'),
      secret: 'secret',
    );

    expect(result, isNull);
  });
}
