import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';

/// System-font theme for widget tests (no Google Fonts network fetch).
ThemeData buildReceiptDropTestTheme() {
  return buildReceiptDropTheme(
    textTheme: Typography.material2021().black.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
  );
}

ThemeData buildReceiptDropTheme({TextTheme? textTheme}) {
  final resolvedTextTheme = textTheme ?? buildReceiptDropTextTheme();
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primaryGreen,
    primary: AppColors.primaryGreen,
    onPrimary: AppColors.textPrimary,
    secondary: AppColors.accentOrange,
    onSecondary: AppColors.textPrimary,
    surface: AppColors.scaffold,
    onSurface: AppColors.textPrimary,
    error: AppColors.destructive,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.scaffold,
    textTheme: resolvedTextTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.scaffold,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: resolvedTextTheme.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: AppColors.cardSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.cardBorderRadius,
        side: const BorderSide(color: AppColors.divider, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardSurface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
        borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
      ),
      labelStyle: resolvedTextTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      hintStyle: resolvedTextTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: resolvedTextTheme.labelLarge?.copyWith(color: AppColors.textPrimary),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        ),
        textStyle: resolvedTextTheme.labelLarge,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.scaffold,
      selectedColor: AppColors.primaryGreen.withValues(alpha: 0.12),
      labelStyle: resolvedTextTheme.labelMedium!,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.chipBorderRadius,
        side: const BorderSide(color: AppColors.divider),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryGreen,
      foregroundColor: AppColors.textPrimary,
      elevation: 4,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.heroRadius),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
      ),
    ),
  );
}
