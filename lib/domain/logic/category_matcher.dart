import 'dart:convert';

/// Result of applying keyword rules to a merchant string.
class CategoryGuess {
  const CategoryGuess({required this.category});
  final String category;
}

/// Keyword-based category config (bundled JSON; remote refresh in Task 22).
class CategoryConfig {
  CategoryConfig._({
    required this.version,
    required this.defaultCategory,
    required this.rules,
  });

  final String version;
  final String defaultCategory;
  final List<({String category, List<String> keywords})> rules;

  factory CategoryConfig.fromJson(Map<String, dynamic> json) {
    final rulesJson = json['rules'] as List<dynamic>? ?? [];
    final parsed = <({String category, List<String> keywords})>[];
    for (final r in rulesJson) {
      final map = r as Map<String, dynamic>;
      final category = map['category'] as String;
      final anyOf = (map['any_of'] as List<dynamic>)
          .map((e) => e as String)
          .toList();
      parsed.add((category: category, keywords: anyOf));
    }
    return CategoryConfig._(
      version: json['version'] as String? ?? '',
      defaultCategory: json['default_category'] as String? ?? 'Others',
      rules: parsed,
    );
  }

  /// Case-insensitive substring match; first rule with any keyword wins.
  CategoryGuess guessForMerchant(String merchantRaw) {
    final haystack = merchantRaw.toLowerCase();
    for (final rule in rules) {
      for (final kw in rule.keywords) {
        if (haystack.contains(kw.toLowerCase())) {
          return CategoryGuess(category: rule.category);
        }
      }
    }
    return CategoryGuess(category: defaultCategory);
  }

  /// Tries [merchantRaw] first; if that returns the default, scans the first
  /// [scanLines] lines of [ocrText] for a keyword match.
  ///
  /// Returns `(category, confidence)`:
  ///   - Merchant-name hit → 0.85
  ///   - OCR-body hit      → 0.55
  ///   - No match          → (defaultCategory, 0.10)
  ({String category, double confidence}) guessWithConfidence(
    String merchantRaw,
    String ocrText, {
    int scanLines = 15,
  }) {
    final merchantGuess = guessForMerchant(merchantRaw);
    if (merchantGuess.category != defaultCategory) {
      return (category: merchantGuess.category, confidence: 0.85);
    }

    final lines = ocrText.split(RegExp(r'\r?\n')).take(scanLines);
    for (final line in lines) {
      final haystack = line.toLowerCase();
      for (final rule in rules) {
        for (final kw in rule.keywords) {
          if (haystack.contains(kw.toLowerCase())) {
            return (category: rule.category, confidence: 0.55);
          }
        }
      }
    }

    return (category: defaultCategory, confidence: 0.10);
  }
}
