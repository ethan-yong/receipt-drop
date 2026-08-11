import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../domain/models/avatar_config.dart';

/// Circular profile photo from [avatarUrl], with initials fallback.
///
/// Used anywhere the real Settings/profile-setup photo should appear
/// (map pins, sheets) instead of the stylized yellow [BlobAvatar].
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({
    super.key,
    required this.size,
    this.avatarUrl,
    this.displayName,
    this.fallbackColor,
    this.userId,
  });

  final double size;
  final String? avatarUrl;
  final String? displayName;

  /// Prefer the user's avatar-config swatch when known; otherwise a stable
  /// color derived from [userId] (or a neutral cream).
  final Color? fallbackColor;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _InitialsFallback(
            size: size,
            displayName: displayName,
            color: _resolvedFallbackColor(),
          ),
        ),
      );
    }
    return _InitialsFallback(
      size: size,
      displayName: displayName,
      color: _resolvedFallbackColor(),
    );
  }

  Color _resolvedFallbackColor() {
    if (fallbackColor != null) return fallbackColor!;
    final id = userId;
    if (id != null && id.isNotEmpty) {
      final values = AvatarColorOption.values;
      return values[id.hashCode.abs() % values.length].swatch;
    }
    return AppColors.creamDark;
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({
    required this.size,
    required this.displayName,
    required this.color,
  });

  final double size;
  final String? displayName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textColor =
        color.computeLuminance() > 0.55 ? AppColors.textPrimary : Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        _initialsFor(displayName),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }
}

String _initialsFor(String? name) {
  final parts = (name ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final word = parts.first;
    return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}
