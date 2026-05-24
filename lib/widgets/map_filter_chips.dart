import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class MapFilterChips extends StatelessWidget {
  const MapFilterChips({
    super.key,
    required this.selectedTime,
    required this.onTimeChanged,
    this.categories = const ['All categories'],
    this.selectedCategory = 'All categories',
    this.onCategoryChanged,
  });

  final String selectedTime;
  final ValueChanged<String> onTimeChanged;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String>? onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          _chip(
            context,
            'This month',
            selectedTime == 'This month',
            () => onTimeChanged('This month'),
          ),
          const SizedBox(width: AppSpacing.sm),
          _chip(
            context,
            'Last month',
            selectedTime == 'Last month',
            () => onTimeChanged('Last month'),
          ),
          const SizedBox(width: AppSpacing.sm),
          for (final c in categories)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _chip(
                context,
                c,
                selectedCategory == c,
                () => onCategoryChanged?.call(c),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primaryGreen.withValues(alpha: 0.15),
      checkmarkColor: AppColors.primaryGreen,
      labelStyle: TextStyle(
        color: selected ? AppColors.primaryGreen : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        fontSize: 13,
      ),
    );
  }
}
