import 'package:flutter/material.dart';

/// PuggyBank color tokens (mock: cream + forest green).
abstract final class AppColors {
  static const scaffold = Color(0xFFF9F7F2);
  static const primaryGreen = Color(0xFF2D5A27);
  static const primaryGreenDark = Color(0xFF1E3D1A);
  static const accentOrange = Color(0xFFE67E22);
  static const accentOrangeLight = Color(0xFFFFF3E6);

  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF5C5C5C);
  static const textMuted = Color(0xFF8A8A8A);

  static const cardSurface = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE8E4DC);

  static const badgePendingBg = Color(0xFFFFF3E6);
  static const badgePendingText = Color(0xFFC45A0A);
  static const badgeNeedsAmountBg = Color(0xFFE8F0FE);
  static const badgeNeedsAmountText = Color(0xFF2E5AAC);

  static const destructive = Color(0xFFC0392B);
  static const destructiveLight = Color(0xFFFDECEA);

  static const navUnselected = Color(0xFF6B6B6B);

  static const chartFood = Color(0xFF4A90A4);
  static const chartShopping = Color(0xFFE67E22);
  static const chartTransport = Color(0xFF7D6B9D);
  static const chartGroceries = Color(0xFF6AAF6E);
  static const chartOthers = Color(0xFFB8B0A4);
  static const chartUnclassified = Color(0xFFD4CFC6);

  static Color categoryColor(String category) {
    switch (category) {
      case 'Food & Drink':
        return chartFood;
      case 'Shopping':
        return chartShopping;
      case 'Transport':
        return chartTransport;
      case 'Groceries':
        return chartGroceries;
      case 'Unclassified':
        return chartUnclassified;
      default:
        return chartOthers;
    }
  }
}
