import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Platform detection and scroll behavior helpers.
abstract final class PlatformUtils {
  static bool get isCupertino =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isMobile => isCupertino || isAndroid;

  static ScrollPhysics listPhysics(BuildContext context) {
    if (isCupertino) {
      return const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      );
    }
    return const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    );
  }
}
