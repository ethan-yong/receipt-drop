import 'package:flutter/material.dart';

/// Port of Impact Drops' `diorama-themes.ts` — 11 category-themed palettes
/// used as 2D illustrated scene backgrounds (see widgets/themed_scene_background.dart)
/// in place of the source's 3D CSS/Three.js diorama rooms.
enum DioramaThemeId {
  idle,
  grocery,
  petrol,
  cafe,
  shopping,
  fastFood,
  gym,
  electronics,
  beauty,
  transport,
  home,
}

class DioramaTheme {
  const DioramaTheme({
    required this.id,
    required this.label,
    required this.floor,
    required this.wallA,
    required this.wallB,
    required this.accent,
    required this.trim,
    required this.caption,
  });

  final DioramaThemeId id;
  final String label;
  final Color floor;
  final Color wallA;
  final Color wallB;
  final Color accent;
  final Color trim;
  final String caption;
}

const Map<DioramaThemeId, DioramaTheme> dioramaThemes = {
  DioramaThemeId.idle: DioramaTheme(
    id: DioramaThemeId.idle,
    label: 'Empty Room',
    floor: Color(0xFFDCD7C9),
    wallA: Color(0xFFF6F2E7),
    wallB: Color(0xFFEAE4D6),
    accent: Color(0xFFD0B56A),
    trim: Color(0xFF8C694E),
    caption: "We couldn't identify your last receipt. Update it to unlock your space.",
  ),
  DioramaThemeId.grocery: DioramaTheme(
    id: DioramaThemeId.grocery,
    label: 'Grocery Store',
    floor: Color(0xFFDCD7C9),
    wallA: Color(0xFFE6E7C9),
    wallB: Color(0xFFC0DCA5),
    accent: Color(0xFF48A830),
    trim: Color(0xFF7D5B40),
    caption: 'Your last receipt was from groceries 🛒',
  ),
  DioramaThemeId.petrol: DioramaTheme(
    id: DioramaThemeId.petrol,
    label: 'Petrol Station',
    floor: Color(0xFF77818C),
    wallA: Color(0xFFB4D3E3),
    wallB: Color(0xFF0F74C5),
    accent: Color(0xFFFF614D),
    trim: Color(0xFF262F38),
    caption: 'Your last receipt was from a petrol station ⛽',
  ),
  DioramaThemeId.cafe: DioramaTheme(
    id: DioramaThemeId.cafe,
    label: 'Cozy Cafe',
    floor: Color(0xFFD0B198),
    wallA: Color(0xFFF0F1D3),
    wallB: Color(0xFF7D460B),
    accent: Color(0xFF974D00),
    trim: Color(0xFF5C412C),
    caption: 'Your last receipt was from a cafe ☕',
  ),
  DioramaThemeId.shopping: DioramaTheme(
    id: DioramaThemeId.shopping,
    label: 'Clothing Store',
    floor: Color(0xFFFDDAE3),
    wallA: Color(0xFFFFD8E6),
    wallB: Color(0xFFFFB3D7),
    accent: Color(0xFFFB5C99),
    trim: Color(0xFF8D6760),
    caption: 'Your last receipt was from shopping 🛍️',
  ),
  DioramaThemeId.fastFood: DioramaTheme(
    id: DioramaThemeId.fastFood,
    label: 'Fast Food',
    floor: Color(0xFFF9DFCB),
    wallA: Color(0xFFFFE6D1),
    wallB: Color(0xFFF84331),
    accent: Color(0xFFF84331),
    trim: Color(0xFF5F4025),
    caption: 'Your last receipt was from fast food 🍔',
  ),
  DioramaThemeId.gym: DioramaTheme(
    id: DioramaThemeId.gym,
    label: 'Gym',
    floor: Color(0xFF95A0AB),
    wallA: Color(0xFFC4CFDB),
    wallB: Color(0xFFA9B9CA),
    accent: Color(0xFFE85A48),
    trim: Color(0xFF333C45),
    caption: 'Your last receipt was from a gym 💪',
  ),
  DioramaThemeId.electronics: DioramaTheme(
    id: DioramaThemeId.electronics,
    label: 'Gaming Store',
    floor: Color(0xFF2A2C42),
    wallA: Color(0xFF1C1D3E),
    wallB: Color(0xFF551F60),
    accent: Color(0xFFFA87FF),
    trim: Color(0xFF131428),
    caption: 'Your last receipt was from electronics 🎮',
  ),
  DioramaThemeId.beauty: DioramaTheme(
    id: DioramaThemeId.beauty,
    label: 'Beauty Room',
    floor: Color(0xFFFFDDE7),
    wallA: Color(0xFFFFE1ED),
    wallB: Color(0xFFFFC2DF),
    accent: Color(0xFFF68FD5),
    trim: Color(0xFF91645D),
    caption: 'Your last receipt was from beauty ✨',
  ),
  DioramaThemeId.transport: DioramaTheme(
    id: DioramaThemeId.transport,
    label: 'Transit Platform',
    floor: Color(0xFF9BA6B1),
    wallA: Color(0xFFBBD2DE),
    wallB: Color(0xFF397A97),
    accent: Color(0xFF0099F0),
    trim: Color(0xFF262F38),
    caption: 'Your last receipt was from transport 🚇',
  ),
  DioramaThemeId.home: DioramaTheme(
    id: DioramaThemeId.home,
    label: 'Home',
    floor: Color(0xFFBD9E86),
    wallA: Color(0xFFD8CCB8),
    wallB: Color(0xFFCBBBA1),
    accent: Color(0xFFCF6139),
    trim: Color(0xFF6E4D32),
    caption: 'Your last receipt was for home expenses 🏠',
  ),
};

/// Forgiving category → theme mapping, ported verbatim from
/// `getThemeForCategory()`. Fed the app's real `effectiveCategory` strings
/// (currently a coarser set than Impact Drops implies — see plan notes —
/// so most receipts land on idle/grocery/transport/fast_food until the
/// bundled category config gains more rules).
DioramaTheme getThemeForCategory(String? category) {
  final idle = dioramaThemes[DioramaThemeId.idle]!;
  if (category == null || category.isEmpty) return idle;
  final c = category.toLowerCase();

  const match = <(List<String>, DioramaThemeId)>[
    (['grocery', 'groceries', 'market', 'supermarket'], DioramaThemeId.grocery),
    (['fuel', 'petrol', 'gas', 'station'], DioramaThemeId.petrol),
    (['coffee', 'cafe', 'espresso', 'latte', 'tea', 'boba', 'bubble'], DioramaThemeId.cafe),
    (['clothes', 'clothing', 'fashion', 'shop', 'shopping', 'mall', 'boutique'], DioramaThemeId.shopping),
    (['fast food', 'fastfood', 'burger', 'takeaway', 'takeout', 'fries', 'mcd', 'kfc'], DioramaThemeId.fastFood),
    (['gym', 'fitness', 'workout', 'yoga'], DioramaThemeId.gym),
    (['electronics', 'gaming', 'game', 'console', 'tech', 'pc'], DioramaThemeId.electronics),
    (['beauty', 'cosmetics', 'skincare', 'makeup', 'salon'], DioramaThemeId.beauty),
    (['transport', 'transit', 'train', 'mrt', 'bus', 'ticket', 'grab', 'uber'], DioramaThemeId.transport),
    (['bill', 'utility', 'rent', 'home', 'internet', 'electric', 'water'], DioramaThemeId.home),
    // Legacy fall-throughs to keep older categories useful.
    (['food', 'restaurant', 'meal', 'dining'], DioramaThemeId.fastFood),
  ];

  for (final (keys, id) in match) {
    if (keys.any(c.contains)) return dioramaThemes[id]!;
  }
  return idle;
}
