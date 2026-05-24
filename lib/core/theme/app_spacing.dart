import 'package:flutter/material.dart';

/// Spacing and shape tokens.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  static const double cardRadius = 16;
  static const double chipRadius = 20;
  static const double buttonRadius = 14;
  static const double inputRadius = 12;

  static const EdgeInsets screenPadding =
      EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);

  static BorderRadius get cardBorderRadius =>
      BorderRadius.circular(cardRadius);
  static BorderRadius get chipBorderRadius =>
      BorderRadius.circular(chipRadius);
}
