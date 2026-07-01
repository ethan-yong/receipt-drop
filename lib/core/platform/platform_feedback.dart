import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'platform_utils.dart';

/// Haptics, toasts, and transient overlays with platform-appropriate styling.
abstract final class PlatformFeedback {
  static void lightTap() {
    if (!PlatformUtils.isMobile) return;
    HapticFeedback.lightImpact();
  }

  static void mediumTap() {
    if (!PlatformUtils.isMobile) return;
    HapticFeedback.mediumImpact();
  }

  static void selectionTap() {
    if (!PlatformUtils.isMobile) return;
    HapticFeedback.selectionClick();
  }

  static void errorTap() {
    if (!PlatformUtils.isMobile) return;
    HapticFeedback.heavyImpact();
  }

  static void showMessage(BuildContext context, String message) {
    if (PlatformUtils.isCupertino) {
      _showCupertinoBanner(context, message, isError: false);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static void showError(BuildContext context, String message) {
    errorTap();
    if (PlatformUtils.isCupertino) {
      _showCupertinoBanner(context, message, isError: true);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.destructive,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  static void _showCupertinoBanner(
    BuildContext context,
    String message, {
    required bool isError,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          top: MediaQuery.paddingOf(ctx).top + 8,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: isError
                      ? AppColors.destructiveLight
                      : CupertinoColors.systemGrey6.resolveFrom(ctx),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isError
                        ? AppColors.destructive.withValues(alpha: 0.3)
                        : CupertinoColors.separator.resolveFrom(ctx),
                  ),
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        color: isError
                            ? AppColors.destructive
                            : AppColors.textPrimary,
                      ),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 3), entry.remove);
  }

  static OverlayEntry? _ocrEntry;

  static void showOcrProgress(BuildContext context, {String? merchantHint}) {
    hideOcrProgress();
    final overlay = Overlay.of(context);
    final message = merchantHint != null && merchantHint.isNotEmpty
        ? 'Reading $merchantHint receipt…'
        : 'Reading your receipt…';

    _ocrEntry = OverlayEntry(
      builder: (ctx) {
        final child = PlatformUtils.isCupertino
            ? CupertinoActivityIndicator(radius: 14)
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              );

        return Material(
          color: Colors.black38,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  child,
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    message,
                    style: Theme.of(ctx).textTheme.titleSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_ocrEntry!);
  }

  static void hideOcrProgress() {
    _ocrEntry?.remove();
    _ocrEntry = null;
  }
}
