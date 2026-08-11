import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a badge art asset — SVG (existing catalog) or PNG (photo icons).
Widget badgeIconAsset(
  String asset, {
  required double width,
  required double height,
}) {
  if (asset.toLowerCase().endsWith('.png') ||
      asset.toLowerCase().endsWith('.jpg') ||
      asset.toLowerCase().endsWith('.jpeg') ||
      asset.toLowerCase().endsWith('.webp')) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
  return SvgPicture.asset(
    asset,
    width: width,
    height: height,
  );
}
