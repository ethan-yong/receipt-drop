import 'dart:convert';

import 'package:flutter/services.dart';

class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.label,
    required this.description,
    required this.svgAsset,
    required this.tierGoals,
    required this.tierUnit,
    this.comingSoon = false,
  });

  final String id;
  final String label;
  final String description;
  final String svgAsset;
  final List<int> tierGoals;
  final String tierUnit;
  final bool comingSoon;

  bool get isTiered => true;
}

/// Static badge catalog — curated, ship-with-the-app content. Per-user
/// runtime state (earned/progress) lives in Supabase `user_badges`.
class BadgeCatalog {
  BadgeCatalog._(this.badges);

  final List<BadgeDef> badges;

  static Future<BadgeCatalog> loadBundled() async {
    final raw = await rootBundle.loadString('assets/config/badges-v1.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['badges'] as List<dynamic>).map((e) {
      final map = e as Map<String, dynamic>;
      final tierGoalsRaw = map['tierGoals'] as List<dynamic>;
      return BadgeDef(
        id: map['id'] as String,
        label: map['label'] as String,
        description: map['description'] as String,
        svgAsset: map['svgAsset'] as String,
        tierGoals: tierGoalsRaw.map((g) => g as int).toList(),
        tierUnit: map['tierUnit'] as String,
        comingSoon: map['comingSoon'] as bool? ?? false,
      );
    }).toList();
    return BadgeCatalog._(list);
  }

  BadgeDef? byId(String id) {
    for (final b in badges) {
      if (b.id == id) return b;
    }
    return null;
  }
}
