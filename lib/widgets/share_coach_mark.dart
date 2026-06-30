import 'package:flutter/material.dart';

import '../core/bootstrap/app_prefs.dart';
import '../core/theme/app_theme.dart';

/// One-time tip after the first OS share save.
class ShareCoachMark extends StatelessWidget {
  const ShareCoachMark({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentOrangeLight,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.share, color: AppColors.accentOrange, size: 22),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Share works from any app',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.accentOrange,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Open a receipt in your bank or TNG app, tap Share, then '
                    'choose Receipt Drop — no need to open this app first.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.textMuted,
              onPressed: () async {
                await AppPrefs.setShareCoachMarkSeen();
                onDismiss();
              },
            ),
          ],
        ),
      ),
    );
  }
}
