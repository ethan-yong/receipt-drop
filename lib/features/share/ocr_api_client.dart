import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/models/ocr_line.dart';
import '../../domain/models/receipt_understanding.dart';

/// OCR text + mean word confidence from the self-hosted Tesseract OCR API,
/// plus the LLM receipt-understanding the same `/ocr` call now returns
/// synchronously (see `services/ocr-api/app/main.py`).
class OcrApiResult {
  const OcrApiResult({
    required this.text,
    required this.confidence,
    this.lines,
    this.understanding,
    this.understandingError,
  });

  final String text;
  final double confidence;

  /// Per-line text + visual-prominence data, for merchant candidate ranking.
  /// `null` when the server response predates this field (older deployed
  /// instance) or omitted it for any other reason — callers must treat
  /// absence as "no large-text signal available", not an error.
  final List<OcrLine>? lines;

  /// The interpreted receipt, or `null` when OCR found no text or the LLM
  /// call itself failed (see [understandingError]) — the raw [text]/[lines]
  /// above are always usable on their own regardless.
  final ReceiptUnderstanding? understanding;

  /// Machine-readable failure code (e.g. `llm_timeout`, `llm_http_503`) when
  /// [understanding] is `null` but OCR itself succeeded.
  final String? understandingError;
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
  Duration timeout = const Duration(seconds: 65),
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

    final linesJson = decoded['lines'];
    final lines = linesJson is List
        ? [for (final item in linesJson) OcrLine.tryFromJson(item)]
            .whereType<OcrLine>()
            .toList()
        : null;

    final understandingError = decoded['understanding_error'];

    return OcrApiResult(
      text: text,
      confidence: confidence.toDouble(),
      lines: lines,
      understanding: ReceiptUnderstanding.tryFromJson(decoded['understanding']),
      understandingError:
          understandingError is String ? understandingError : null,
    );
  } catch (_) {
    return null;
  } finally {
    if (ownsClient) {
      httpClient.close();
    }
  }
}

/// Default local OCR API URL when running `services/ocr-api` via uvicorn.
Uri defaultOcrApiUrl({String host = '127.0.0.1', int port = 8081}) {
  return Uri.parse('http://$host:$port/ocr');
}
