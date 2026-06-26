import 'dart:convert';

import 'package:flutter/services.dart';

enum BadgeRarity { common, rare, epic, legendary }

BadgeRarity _rarityFromString(String? value) {
  switch (value) {
    case 'rare':
      return BadgeRarity.rare;
    case 'epic':
      return BadgeRarity.epic;
    case 'legendary':
      return BadgeRarity.legendary;
    default:
      return BadgeRarity.common;
  }
}

class BadgeDef {
  const BadgeDef({
    required this.id,
    required this.label,
    required this.emoji,
    required this.description,
    required this.rarity,
    required this.goal,
    this.hint,
  });

  final String id;
  final String label;
  final String emoji;
  final String description;
  final BadgeRarity rarity;
  final int goal;
  final String? hint;
}

/// Static badge catalog (rarity/goal/copy) — curated, ship-with-the-app
/// content, so it follows the bundled-JSON precedent set by
/// `CategoryConfig.loadBundled()` rather than a database table. Per-user
/// runtime state (earned/progress) lives in Supabase `user_badges` instead.
class BadgeCatalog {
  BadgeCatalog._(this.badges);

  final List<BadgeDef> badges;

  static Future<BadgeCatalog> loadBundled() async {
    final raw = await rootBundle.loadString('assets/config/badges-v1.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['badges'] as List<dynamic>).map((e) {
      final map = e as Map<String, dynamic>;
      return BadgeDef(
        id: map['id'] as String,
        label: map['label'] as String,
        emoji: map['emoji'] as String,
        description: map['description'] as String,
        rarity: _rarityFromString(map['rarity'] as String?),
        goal: map['goal'] as int,
        hint: map['hint'] as String?,
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
