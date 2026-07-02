import 'dart:convert';
import 'dart:io';

import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/category_matcher_io.dart';
import 'package:receipt_drop/features/share/ocr_api_client.dart';
import 'package:receipt_drop/features/share/receipt_parse_pipeline.dart';

/// Batch-processes receipt images via the self-hosted OCR API + app parse pipeline.
///
/// ```powershell
/// # OCR API running locally (services/ocr-api):
/// $env:OCR_SHARED_SECRET = "your-secret"
/// dart run bin/process_receipts.dart --receipts-dir receipts
/// ```
Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options == null) {
    _printUsage();
    exit(64);
  }

  final secret = options.secret ?? Platform.environment['OCR_SHARED_SECRET'];
  if (secret == null || secret.isEmpty) {
    stderr.writeln(
      'ERROR: set OCR_SHARED_SECRET or pass --ocr-secret',
    );
    exit(64);
  }

  final receiptsDir = Directory(options.receiptsDir);
  if (!await receiptsDir.exists()) {
    stderr.writeln('ERROR: receipts dir not found: ${options.receiptsDir}');
    exit(1);
  }

  final categoriesFile = File(options.categoriesFile);
  if (!await categoriesFile.exists()) {
    stderr.writeln(
      'ERROR: categories file not found: ${options.categoriesFile}',
    );
    exit(1);
  }

  final categories = await loadCategoryConfigFromFile(options.categoriesFile);
  final ocrUrl = options.ocrUrl ?? defaultOcrApiUrl();

  _log('[receipt_batch] Found ${await _countReceiptFiles(receiptsDir)} receipt file(s)');

  if (options.checkHealth) {
    final healthUrl = ocrUrl.replace(path: '/health', query: null);
    try {
      final client = HttpClient();
      final request = await client.getUrl(healthUrl);
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln('ERROR: OCR API health check failed (${response.statusCode})');
        exit(1);
      }
      client.close();
    } catch (e) {
      stderr.writeln('ERROR: OCR API not reachable at $healthUrl ($e)');
      exit(1);
    }
  }

  final files = <File>[];
  await for (final entity in receiptsDir.list()) {
    if (entity is File && _isReceiptFile(entity.path)) {
      files.add(entity);
    }
  }

  if (files.isEmpty) {
    stderr.writeln(
      'WARNING: no receipt images found in ${options.receiptsDir}',
    );
  }

  final results = <Map<String, dynamic>>[];
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final name = _basename(file.path);
    final mime = mimeFromPath(file.path);

    stdout.writeln('[receipt_batch] Processing $name (${i + 1}/${files.length}) ...');
    stdout.flush();

    if (mime == 'application/pdf') {
      results.add({
        'file': name,
        'error': 'pdf_not_supported_in_batch_cli',
      });
      stdout.writeln(
        '[receipt_batch] ${jsonEncode(results.last)}',
      );
      continue;
    }

    try {
      final ocr = await runOcrApi(
        filePath: file.path,
        mimeType: mime,
        ocrUrl: ocrUrl,
        secret: secret,
      );

      if (ocr == null || ocr.text.trim().isEmpty) {
        results.add({
          'file': name,
          'error': 'ocr_failed_or_empty',
        });
        stdout.writeln('[receipt_batch] ${jsonEncode(results.last)}');
        continue;
      }

      final parsed = parseReceiptOcrText(
        filePath: file.path,
        ocrText: ocr.text,
        categories: categories,
        ocrServiceConfidence: ocr.confidence,
      );

      final json = parsed.toJson(includeOcrText: options.includeOcrText);
      results.add(json);
      stdout.writeln('[receipt_batch] ${jsonEncode(json)}');
    } catch (e) {
      final errorJson = {'file': name, 'error': '$e'};
      results.add(errorJson);
      stdout.writeln('[receipt_batch] ${jsonEncode(errorJson)}');
    }
  }

  final outFile = File('${options.receiptsDir}/_results.json');
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(results),
  );
  stdout.writeln(
    '[receipt_batch] Wrote ${results.length} result(s) to ${outFile.path}',
  );
  stdout.flush();
}

void _log(String message) {
  stdout.writeln(message);
  stdout.flush();
}

Future<int> _countReceiptFiles(Directory receiptsDir) async {
  var count = 0;
  await for (final entity in receiptsDir.list()) {
    if (entity is File && _isReceiptFile(entity.path)) {
      count++;
    }
  }
  return count;
}

class _CliOptions {
  const _CliOptions({
    required this.receiptsDir,
    required this.categoriesFile,
    this.ocrUrl,
    this.secret,
    this.includeOcrText = false,
    this.checkHealth = true,
  });

  final String receiptsDir;
  final String categoriesFile;
  final Uri? ocrUrl;
  final String? secret;
  final bool includeOcrText;
  final bool checkHealth;
}

_CliOptions? _parseArgs(List<String> args) {
  var receiptsDir = 'receipts';
  var categoriesFile = 'assets/config/categories-v1.json';
  Uri? ocrUrl;
  String? secret;
  var includeOcrText = false;
  var checkHealth = true;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--receipts-dir':
        if (++i >= args.length) return null;
        receiptsDir = args[i];
      case '--categories-file':
        if (++i >= args.length) return null;
        categoriesFile = args[i];
      case '--ocr-url':
        if (++i >= args.length) return null;
        ocrUrl = Uri.parse(args[i]);
      case '--ocr-secret':
        if (++i >= args.length) return null;
        secret = args[i];
      case '--include-ocr-text':
        includeOcrText = true;
      case '--skip-health-check':
        checkHealth = false;
      case '--help':
      case '-h':
        return null;
      default:
        stderr.writeln('Unknown argument: $arg');
        return null;
    }
  }

  return _CliOptions(
    receiptsDir: receiptsDir,
    categoriesFile: categoriesFile,
    ocrUrl: ocrUrl,
    secret: secret,
    includeOcrText: includeOcrText,
    checkHealth: checkHealth,
  );
}

void _printUsage() {
  stdout.writeln('''
Usage: dart run bin/process_receipts.dart [options]

Options:
  --receipts-dir <path>       Folder of receipt images (default: receipts)
  --categories-file <path>    Category rules JSON (default: assets/config/categories-v1.json)
  --ocr-url <url>             OCR API endpoint (default: http://127.0.0.1:8080/ocr)
  --ocr-secret <secret>       X-OCR-Secret (default: OCR_SHARED_SECRET env)
  --include-ocr-text          Include raw OCR text in JSON output
  --skip-health-check         Skip GET /health before processing
  -h, --help                  Show this help
''');
}

bool _isReceiptFile(String path) {
  final lower = path.toLowerCase();
  return receiptBatchExtensions.any(lower.endsWith);
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash >= 0 ? normalized.substring(slash + 1) : normalized;
}
