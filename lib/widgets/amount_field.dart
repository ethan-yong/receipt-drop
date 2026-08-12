import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount (MYR)',
    this.onChanged,
    this.bordered = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  /// Wraps the field in a bordered box, separate from the label above it.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      onChanged: onChanged,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.primaryGreen,
          ),
      decoration: const InputDecoration(
        prefixText: 'RM ',
        prefixStyle: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryGreen,
        ),
        border: InputBorder.none,
        filled: false,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (bordered)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.inputRadius),
              border: Border.all(color: AppColors.divider, width: 1.5),
            ),
            child: field,
          )
        else
          field,
      ],
    );
  }
}
