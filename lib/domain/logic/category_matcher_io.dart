import 'dart:convert';
import 'dart:io';

import 'category_matcher.dart';

/// Loads bundled category rules from a JSON file on disk (CLI / batch scripts).
Future<CategoryConfig> loadCategoryConfigFromFile(String path) async {
  final raw = await File(path).readAsString();
  return CategoryConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
