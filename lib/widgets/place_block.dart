import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class PlaceBlock extends StatelessWidget {
  const PlaceBlock({
    super.key,
    required this.placeName,
    required this.onChangePlace,
  });

  final String placeName;
  final VoidCallback onChangePlace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Place', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              child: Container(
                height: 100,
                width: double.infinity,
                color: AppColors.divider,
                child: const Icon(
                  Icons.map_outlined,
                  size: 40,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    placeName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: onChangePlace,
                  child: const Text('Change place'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
