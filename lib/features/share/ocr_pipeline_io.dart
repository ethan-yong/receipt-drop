import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfrx/pdfrx.dart';
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
      return '';
    }
    final page = doc.pages.first;
    final pageText = await page.loadText();
    final text = pageText.fullText;
    await doc.dispose();
    return text;
  } catch (_) {
    return '';
  }
}

Future<String> _ocrImageFile(String imagePath) async {
  try {
    final recognizer = TextRecognizer();
    final input = InputImage.fromFilePath(imagePath);
    final result = await recognizer.processImage(input);
    await recognizer.close();
    return result.text;
  } catch (_) {
    return '';
  }
}
