import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';

const _remoteOcrTimeout = Duration(seconds: 6);
const _remoteOcrAllowedMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

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

/// OCR text plus the engine's scan-quality confidence (null when the source
/// provides none: local ML Kit, PDF text extraction, or web).
typedef OcrFileResult = ({String text, double? serviceConfidence});

/// Runs OCR on receipt images (ML Kit) or extracts text from PDF (pdfrx).
Future<OcrFileResult> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  final isPdf =
      mimeType.contains('pdf') || filePath.toLowerCase().endsWith('.pdf');
  if (isPdf) {
    return (text: await _extractPdfText(filePath), serviceConfidence: null);
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

/// Runs local ML Kit OCR and, when eligible, races it against the
/// self-hosted remote OCR service (better accuracy on messy thermal
/// receipts via server-side deskew/contrast preprocessing). Prefers a
/// non-empty remote result within [_remoteOcrTimeout], else falls back to
/// the local result.
Future<OcrFileResult> _ocrImageFile(String imagePath, String mimeType) async {
  final localFuture = _localOcrImageFile(imagePath);
  if (!_remoteOcrEligible(mimeType)) {
    return (text: await localFuture, serviceConfidence: null);
  }

  final remoteFuture = _remoteOcrImageFile(
    imagePath: imagePath,
    mimeType: mimeType,
  ).timeout(_remoteOcrTimeout, onTimeout: () => null);

  final localText = await localFuture;
  final remote = await remoteFuture;

  if (remote != null && remote.text.trim().isNotEmpty) {
    return (text: remote.text, serviceConfidence: remote.confidence);
  }
  return (text: localText, serviceConfidence: null);
}

Future<String> _localOcrImageFile(String imagePath) async {
  try {
    final recognizer = TextRecognizer();
    final input = InputImage.fromFilePath(imagePath);
    final result = await recognizer.processImage(input);
    await recognizer.close();
    if (result.text.isEmpty) {
      ocrLogger('Image OCR found no text: $imagePath', level: 800);
    }
    return result.text;
  } catch (e, st) {
    ocrLogger(
      'Image OCR failed: $imagePath',
      error: e,
      stackTrace: st,
      level: 1000,
    );
    return '';
  }
}

bool _remoteOcrEligible(String mimeType) {
  if (!Env.hasSupabaseConfig) return false;
  return _remoteOcrAllowedMimeTypes.contains(mimeType.toLowerCase());
}

/// Calls the self-hosted OCR service via the `ocr-proxy` Supabase Edge
/// Function. Returns `null` on any failure so the caller can fall back to
/// the local ML Kit result — never throws.
Future<({String text, double? confidence})?> _remoteOcrImageFile({
  required String imagePath,
  required String mimeType,
}) async {
  try {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) return null;

    final bytes = await File(imagePath).readAsBytes();
    final uri = Uri.parse(
      '${Env.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/ocr-proxy',
    );
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'apikey': Env.supabaseAnonKey,
        'Content-Type': mimeType,
      },
      body: bytes,
    );

    if (response.statusCode != 200) {
      ocrLogger(
        'Remote OCR request failed: $imagePath (status ${response.statusCode})',
        level: 800,
      );
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final text = decoded['text'];
    if (text is! String) return null;
    final confidence = decoded['confidence'];
    return (
      text: text,
      confidence: confidence is num ? confidence.toDouble() : null,
    );
  } catch (e, st) {
    ocrLogger(
      'Remote OCR failed: $imagePath',
      error: e,
      stackTrace: st,
      level: 400,
    );
    return null;
  }
}
