import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Plus Jakarta Sans throughout, per the Impact Drops design system.
TextTheme buildReceiptDropTextTheme() {
  final display = GoogleFonts.plusJakartaSans(
    color: AppColors.textPrimary,
    fontWeight: FontWeight.w800,
  );
  final body = GoogleFonts.plusJakartaSans(
    color: AppColors.textPrimary,
  );

  return TextTheme(
    displayLarge: display.copyWith(fontSize: 32, height: 1.15),
    displayMedium: display.copyWith(fontSize: 28, height: 1.2),
    displaySmall: display.copyWith(fontSize: 24, height: 1.25),
    headlineMedium: display.copyWith(fontSize: 22),
    headlineSmall: display.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
    titleLarge: body.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
    titleMedium: body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: body.copyWith(fontSize: 16, height: 1.5),
    bodyMedium: body.copyWith(fontSize: 14, height: 1.45),
    bodySmall: body.copyWith(
      fontSize: 12,
      height: 1.4,
      color: AppColors.textSecondary,
    ),
    labelLarge: body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    ),
    labelMedium: body.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.textSecondary,
    ),
    labelSmall: body.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: AppColors.textMuted,
    ),
  );
}
