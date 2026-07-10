import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../domain/models/ocr_line.dart';
import '../../domain/models/receipt_understanding.dart';
import 'ocr_api_client.dart';

const _ocrProxyTimeout = Duration(seconds: 30);
const _ocrImageMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

typedef OcrLogger = void Function(
  String message, {
  Object? error,
  StackTrace? stackTrace,
  int level,
});

/// Overridable in tests to capture log calls without a logging package.
OcrLogger ocrLogger = _defaultOcrLog;

void _defaultOcrLog(
  String message, {
  Object? error,
  StackTrace? stackTrace,
  int level = 0,
}) {
  developer.log(
    message,
    name: 'ocr_pipeline',
    error: error,
    stackTrace: stackTrace,
    level: level,
  );
}

/// OCR text plus the engine's scan-quality confidence (null for PDF text
/// extraction when no OCR service ran), per-line visual-prominence data for
/// merchant candidate ranking when available, and the LLM receipt
/// understanding the OCR service now returns synchronously in the same call
/// (null for PDFs — the LLM only ever runs inside the OCR service's /ocr,
/// which PDFs never hit; pdfrx already yields clean text).
typedef OcrFileResult = ({
  String text,
  double? serviceConfidence,
  List<OcrLine>? lines,
  ReceiptUnderstanding? understanding,
  String? understandingError,
});

/// Runs OCR on receipt images via the self-hosted OCR API, or extracts text
/// from PDF (pdfrx). No on-device ML Kit fallback.
Future<OcrFileResult> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  final isPdf =
      mimeType.contains('pdf') || filePath.toLowerCase().endsWith('.pdf');
  if (isPdf) {
    return (
      text: await _extractPdfText(filePath),
      serviceConfidence: null,
      lines: null,
      understanding: null,
      understandingError: null,
    );
  }
  return _ocrImageFile(filePath, mimeType);
}

Future<String> _extractPdfText(String pdfPath) async {
  try {
    final doc = await PdfDocument.openFile(pdfPath);
    if (doc.pages.isEmpty) {
      await doc.dispose();
      ocrLogger('PDF has no pages: $pdfPath', level: 800);
      return '';
    }
    final page = doc.pages.first;
    final pageText = await page.loadText();
    final text = pageText.fullText;
    await doc.dispose();
    if (text.isEmpty) {
      ocrLogger('PDF text extraction returned no text: $pdfPath', level: 800);
    }
    return text;
  } catch (e, st) {
    ocrLogger(
      'PDF text extraction failed: $pdfPath',
      error: e,
      stackTrace: st,
      level: 1000,
    );
    return '';
  }
}

Future<OcrFileResult> _ocrImageFile(String imagePath, String mimeType) async {
  const empty = (
    text: '',
    serviceConfidence: null,
    lines: null,
    understanding: null,
    understandingError: null,
  );

  if (!_ocrImageMimeTypes.contains(mimeType.toLowerCase())) {
    ocrLogger('Unsupported MIME for OCR: $mimeType', level: 800);
    return empty;
  }

  if (Env.hasOcrApiConfig) {
    final direct = await runOcrApi(
      filePath: imagePath,
      mimeType: mimeType,
      ocrUrl: Uri.parse(Env.ocrApiUrl),
      secret: Env.ocrSharedSecret,
    );
    if (direct != null && direct.text.trim().isNotEmpty) {
      return (
        text: direct.text,
        serviceConfidence: direct.confidence,
        lines: direct.lines,
        understanding: direct.understanding,
        understandingError: direct.understandingError,
      );
    }
    ocrLogger(
      'Direct OCR API returned no text: $imagePath',
      level: 800,
    );
    return empty;
  }

  if (Env.hasSupabaseConfig) {
    final proxied = await _ocrViaSupabaseProxy(
      imagePath: imagePath,
      mimeType: mimeType,
    );
    if (proxied != null && proxied.text.trim().isNotEmpty) {
      return (
        text: proxied.text,
        serviceConfidence: proxied.confidence,
        lines: proxied.lines,
        understanding: proxied.understanding,
        understandingError: proxied.understandingError,
      );
    }
    ocrLogger(
      'OCR proxy returned no text: $imagePath',
      level: 800,
    );
    return empty;
  }

  ocrLogger(
    'OCR unavailable: set OCR_API_URL + OCR_SHARED_SECRET in .env, '
    'or configure Supabase and sign in for ocr-proxy',
    level: 1000,
  );
  return empty;
}

/// Calls the self-hosted OCR service via the `ocr-proxy` Supabase Edge
/// Function. Returns `null` on any failure — never throws.
Future<
    ({
      String text,
      double? confidence,
      List<OcrLine>? lines,
      ReceiptUnderstanding? understanding,
      String? understandingError,
    })?> _ocrViaSupabaseProxy({
  required String imagePath,
  required String mimeType,
}) async {
  try {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      ocrLogger('OCR proxy skipped: no auth session', level: 800);
      return null;
    }

    final bytes = await File(imagePath).readAsBytes();
    final uri = Uri.parse(
      '${Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/ocr-proxy',
    );
    final response = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'apikey': Env.supabaseAnonKey,
            'Content-Type': mimeType,
          },
          body: bytes,
        )
        .timeout(_ocrProxyTimeout);

    if (response.statusCode != 200) {
      ocrLogger(
        'OCR proxy request failed: $imagePath (status ${response.statusCode})',
        level: 800,
      );
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final text = decoded['text'];
    if (text is! String) return null;
    final confidence = decoded['confidence'];
    final linesJson = decoded['lines'];
    final lines = linesJson is List
        ? [for (final item in linesJson) OcrLine.tryFromJson(item)]
            .whereType<OcrLine>()
            .toList()
        : null;
    final understandingError = decoded['understanding_error'];
    return (
      text: text,
      confidence: confidence is num ? confidence.toDouble() : null,
      lines: lines,
      understanding: ReceiptUnderstanding.tryFromJson(decoded['understanding']),
      understandingError:
          understandingError is String ? understandingError : null,
    );
  } catch (e, st) {
    ocrLogger(
      'OCR proxy failed: $imagePath',
      error: e,
      stackTrace: st,
      level: 400,
    );
    return null;
  }
}
