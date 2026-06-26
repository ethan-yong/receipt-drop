import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_utils.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/pug_mascot.dart';
import '../../widgets/puggy_primary_button.dart';
import 'receipt_capture_flow.dart';

class ShareHintScreen extends StatelessWidget {
  const ShareHintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isIos = PlatformUtils.isCupertino;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Share a receipt'),
        leading: IconButton(
          icon: Icon(isIos ? CupertinoIcons.xmark : Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: PugMascot(size: 100)),
            const SizedBox(height: AppSpacing.lg),
            Text(
              isIos ? 'Share from any app' : 'Share from your bank app',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _ShareStep(
              number: 1,
              title: isIos ? 'Open the receipt' : 'Open Maybank, TNG, or Grab',
              subtitle: isIos
                  ? 'In your bank or e-wallet app, open the transaction or receipt screen.'
                  : 'Go to your transaction history and open the receipt you want to track.',
            ),
            _ShareStep(
              number: 2,
              title: 'Tap Share',
              subtitle: isIos
                  ? 'Tap the Share button — usually at the bottom of the screen or in the top-right menu.'
                  : 'Tap the Share icon in the app toolbar or receipt menu.',
            ),
            _ShareStep(
              number: 3,
              title: 'Choose PuggyBank',
              subtitle: isIos
                  ? 'Scroll the share sheet and tap PuggyBank. We read the amount and save it to your feed.'
                  : 'Pick PuggyBank from the share targets. We extract the amount when possible.',
              highlight: true,
            ),
            const Spacer(),
            PuggyPrimaryButton(
              label: 'Upload instead',
              onPressed: () => ReceiptCaptureFlow.start(context),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareStep extends StatelessWidget {
  const _ShareStep({
    required this.number,
    required this.title,
    required this.subtitle,
    this.highlight = false,
  });

  final int number;
  final String title;
  final String subtitle;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: highlight
                ? AppColors.primaryGreen
                : AppColors.divider,
            child: Text(
              '$number',
              style: TextStyle(
                color: highlight ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: highlight ? AppColors.primaryGreen : null,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
