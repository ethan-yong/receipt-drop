import 'package:flutter/material.dart';

class AppColors {
  static const scaffold = Color(0xFFF9F7F2);
  static const primaryGreen = Color(0xFF2D5A27);
  static const accentOrange = Color(0xFFE67E22);
}

ThemeData buildPuggyTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primaryGreen,
      primary: AppColors.primaryGreen,
      secondary: AppColors.accentOrange,
      surface: AppColors.scaffold,
    ),
    scaffoldBackgroundColor: AppColors.scaffold,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.scaffold,
      foregroundColor: Colors.black87,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: AppColors.primaryGreen.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryGreen,
      foregroundColor: Colors.white,
    ),
  );
}
