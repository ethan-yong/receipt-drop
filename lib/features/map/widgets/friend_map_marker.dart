import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repositories/social_repository.dart';
import '../../../domain/logic/avatar_mood.dart';
import '../../../domain/models/avatar_config.dart';
import '../../../widgets/blob_avatar.dart';

/// Snapchat-style friend pin: the friend's BlobAvatar in a white ring with a
/// first-name chip beneath. `animate: false` is load-bearing — every
/// BlobAvatar owns an AnimationController, and dozens of repeating tickers on
/// a pannable map would tank frame rate.
class FriendMapMarker extends StatelessWidget {
  const FriendMapMarker({
    super.key,
    required this.pin,
    required this.onTap,
  });

  final FriendMapPin pin;
  final VoidCallback onTap;

  String get _firstName {
    final name = pin.displayName?.trim();
    if (name == null || name.isEmpty) return 'Friend';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final config = pin.avatarConfigJson != null
        ? AvatarConfig.fromJson(pin.avatarConfigJson!)
        : AvatarConfig.defaultConfig();

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: RepaintBoundary(
              child: BlobAvatar(
                mood: moodFromName(pin.currentMood),
                config: config,
                size: 44,
                animate: false,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3,
                ),
              ],
            ),
            child: Text(
              _firstName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
