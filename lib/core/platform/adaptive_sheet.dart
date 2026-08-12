import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'platform_utils.dart';

/// Presents action menus and forms using platform-native surfaces.
abstract final class AdaptiveSheet {
  /// Depth of currently-open adaptive sheets / immersive overlays.
  /// [MainShell] hides its capture FAB and bottom tab bar while this is > 0
  /// — both live on the shell Scaffold and would otherwise paint above
  /// nested sheets and the map pin detail sheet. Also bumped by the spend
  /// map while a pin detail sheet is open.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  static Future<T?> _trackOpen<T>(Future<T?> future) async {
    openCount.value++;
    try {
      return await future;
    } finally {
      openCount.value--;
    }
  }

  static Future<T?> showActions<T>({
    required BuildContext context,
    required String title,
    required List<AdaptiveAction<T>> actions,
  }) {
    if (PlatformUtils.isCupertino) {
      return _trackOpen(showCupertinoModalPopup<T>(
        context: context,
        // Cover MainShell's center-docked capture FAB and bottom nav.
        useRootNavigator: true,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(title),
          actions: [
            for (final action in actions)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, action.value),
                child: Text(action.label),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ),
      ));
    }

    return _trackOpen(showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final action in actions)
                ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  onTap: () => Navigator.pop(ctx, action.value),
                ),
            ],
          ),
        ),
      ),
    ));
  }

  static Future<T?> showForm<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true,
    Color? backgroundColor,
    double? topRadius,
    bool showDragHandle = true,
  }) {
    if (PlatformUtils.isCupertino) {
      return _trackOpen(showCupertinoModalPopup<T>(
        context: context,
        // Cover MainShell's center-docked capture FAB and bottom nav —
        // without this the FAB paints above quantity / confirm sheets.
        useRootNavigator: true,
        builder: (ctx) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
                ),
                margin: const EdgeInsets.only(top: 48),
                decoration: BoxDecoration(
                  color: backgroundColor ?? AppColors.cardSurface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(topRadius ?? 16),
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: child,
                ),
              ),
            ),
          );
        },
      ));
    }

    return _trackOpen(showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      shape: topRadius != null
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(topRadius),
              ),
            )
          : null,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: child,
      ),
    ));
  }
}

class AdaptiveAction<T> {
  const AdaptiveAction({
    required this.label,
    required this.icon,
    required this.value,
  });

  final String label;
  final IconData icon;
  final T value;
}
