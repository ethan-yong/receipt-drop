import 'dart:convert';

import 'dart:convert';

import 'package:flutter/services.dart';

import 'category_matcher.dart';

/// Loads bundled category rules from Flutter assets (app / widget tests).
Future<CategoryConfig> loadBundledCategoryConfig() async {
  final raw = await rootBundle.loadString('assets/config/categories-v1.json');
  return CategoryConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
