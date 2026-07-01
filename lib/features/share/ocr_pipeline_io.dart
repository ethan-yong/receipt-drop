import 'dart:developer' as developer;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';

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

/// Runs OCR on receipt images (ML Kit) or extracts text from PDF (pdfrx).
Future<String> runOcrOnReceiptFile({
  required String filePath,
  required String mimeType,
}) async {
  final isPdf =
      mimeType.contains('pdf') || filePath.toLowerCase().endsWith('.pdf');
  if (isPdf) {
    return _extractPdfText(filePath);
  }
  return _ocrImageFile(filePath);
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

Future<String> _ocrImageFile(String imagePath) async {
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
