import 'package:flutter/material.dart';

/// Color tokens (warm cream + Impact Drops yellow palette).
abstract final class AppColors {
  static const scaffold = Color(0xFFFCFAF1);
  static const primaryGreen = Color(0xFFFFD32E);
  static const primaryGreenDark = Color(0xFFB48900);
  static const accentOrange = Color(0xFFF88F4F);
  static const accentOrangeLight = Color(0xFFFFDAC2);

  static const textPrimary = Color(0xFF1B150B);
  static const textSecondary = Color(0xFF645D51);
  static const textMuted = Color(0xFF8C8579);

  static const cardSurface = Color(0xFFFFFFFF);
  static const divider = Color(0xFFE5E1D6);
  static const creamDark = Color(0xFFF3EEDD);

  static const badgePendingBg = Color(0xFFFFF3E6);
  static const badgePendingText = Color(0xFFC45A0A);
  static const badgeNeedsAmountBg = Color(0xFFE8F0FE);
  static const badgeNeedsAmountText = Color(0xFF2E5AAC);

  static const destructive = Color(0xFFF94239);
  static const destructiveLight = Color(0xFFFFE5E0);

  // Insight card metric badges — up (spend increase) vs. down (decrease).
  static const insightAlert = Color(0xFFB4483B);
  static const insightGood = Color(0xFF3F7D4A);
  static const insightNeutralOnDark = Color(0xFFF6C64B);

  // Dark-variant insight card (forecast) — bg reuses textPrimary, this is
  // its secondary/supporting text color.
  static const onDarkCardSecondary = Color(0xFFD8D2C4);

  static const navUnselected = Color(0xFF8C8579);

  static const chartFood = Color(0xFF4A90A4);
  static const chartShopping = Color(0xFFE67E22);
  static const chartTransport = Color(0xFF7D6B9D);
  static const chartGroceries = Color(0xFF6AAF6E);
  static const chartTravel = Color(0xFF4E7FE0);
  static const chartHealthBeauty = Color(0xFFE0729A);
  static const chartOthers = Color(0xFFB8B0A4);
  static const chartUnclassified = Color(0xFFD4CFC6);

  // Avatar mood colors.
  static const moodCalm = Color(0xFF6BD8DE);
  static const moodActive = Color(0xFFADE173);
  static const moodSpiky = Color(0xFFFF694D);
  static const moodBalanced = Color(0xFFECCA6C);

  // Impact-level colors (qualitative, never numeric).
  static const impactLow = Color(0xFF7EE3D0);
  static const impactMed = Color(0xFFF1C955);
  static const impactHigh = Color(0xFFFF6247);

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
      case 'Travel':
        return chartTravel;
      case 'Health & Beauty':
        return chartHealthBeauty;
      case 'Unclassified':
        return chartUnclassified;
      default:
        return chartOthers;
    }
  }
}
