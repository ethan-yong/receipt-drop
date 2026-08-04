import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography for the Leaderboard screen — Baloo 2 per the Leaderboard.dc.html
/// handoff (same rounded voice as Receipt History / receipt sheets).
TextStyle leaderboardText(
  double size,
  FontWeight weight, {
  Color color = AppColors.textPrimary,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.baloo2(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

/// Gold score accent for the #1 podium spot in the handoff.
const leaderboardFirstPlaceScore = AppColors.primaryGreenDark;
