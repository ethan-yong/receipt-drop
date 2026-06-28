import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/config/env.dart';
import '../core/platform/platform_feedback.dart';
import '../core/platform/platform_utils.dart';
import '../core/theme/app_theme.dart';

/// Inline sync failure notice — banner on Android, inset alert on iOS.
class AdaptiveSyncBanner extends StatelessWidget {
  const AdaptiveSyncBanner({
    super.key,
    required this.stuckCount,
    required this.onRetry,
  });

  final int stuckCount;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (stuckCount <= 0 || !Env.hasSupabaseConfig) {
      return const SizedBox.shrink();
    }

    final message =
        '$stuckCount receipt${stuckCount > 1 ? 's' : ''} couldn\'t sync';

    if (PlatformUtils.isCupertino) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          0,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.destructiveLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            onPressed: () {
              PlatformFeedback.lightTap();
              onRetry();
            },
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: AppColors.destructive,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '$message — tap to retry',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.destructive,
                        ),
                  ),
                ),
                const Icon(
                  CupertinoIcons.refresh,
                  color: AppColors.destructive,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return MaterialBanner(
      backgroundColor: AppColors.destructiveLight,
      content: Text(message),
      leading: const Icon(Icons.sync_problem, color: AppColors.destructive),
      actions: [
        TextButton(
          onPressed: () {
            PlatformFeedback.lightTap();
            onRetry();
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }
}
