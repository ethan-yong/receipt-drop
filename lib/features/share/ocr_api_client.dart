import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// OCR text + mean line confidence from the self-hosted PaddleOCR API.
class OcrApiResult {
  const OcrApiResult({required this.text, required this.confidence});

  final String text;
  final double confidence;
}

const ocrApiAllowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

/// Calls `POST {ocrUrl}` with raw image bytes and `X-OCR-Secret`.
///
/// Returns `null` on any failure (mirrors remote OCR fallback semantics).
Future<OcrApiResult?> runOcrApi({
  required String filePath,
  required String mimeType,
  required Uri ocrUrl,
  required String secret,
  Duration timeout = const Duration(seconds: 30),
  http.Client? client,
}) async {
  if (!ocrApiAllowedMimeTypes.contains(mimeType.toLowerCase())) {
    return null;
  }

  final httpClient = client ?? http.Client();
  final ownsClient = client == null;

  try {
    final bytes = await File(filePath).readAsBytes();
    final response = await httpClient
        .post(
          ocrUrl,
          headers: {
            'X-OCR-Secret': secret,
            'Content-Type': mimeType,
          },
          body: bytes,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final text = decoded['text'];
    final confidence = decoded['confidence'];
    if (text is! String || confidence is! num) return null;

    return OcrApiResult(text: text, confidence: confidence.toDouble());
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) {
      httpClient.close();
    }
  }
}

/// Default local OCR API URL when running `services/ocr-api` via uvicorn.
Uri defaultOcrApiUrl({String host = '127.0.0.1', int port = 8080}) {
  return Uri.parse('http://$host:$port/ocr');
}
