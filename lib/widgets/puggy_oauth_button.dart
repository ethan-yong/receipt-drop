import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class PuggyOAuthButton extends StatelessWidget {
  const PuggyOAuthButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          backgroundColor: AppColors.cardSurface,
        ),
      ),
    );
  }
}
