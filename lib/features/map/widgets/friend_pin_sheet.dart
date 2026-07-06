import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/social_repository.dart';
import '../../../domain/logic/avatar_mood.dart';
import '../../../domain/models/avatar_config.dart';
import '../../../widgets/blob_avatar.dart';

/// Small modal shown when tapping a friend's map pin: who, where, when.
/// Deliberately amount-free, matching the feed's privacy stance.
class FriendPinSheet extends StatelessWidget {
  const FriendPinSheet({super.key, required this.pin});

  final FriendMapPin pin;

  static Future<void> show(BuildContext context, FriendMapPin pin) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (_) => FriendPinSheet(pin: pin),
    );
  }

  String _relativeTime(DateTime when, DateTime now) {
    final diff = now.difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final config = pin.avatarConfigJson != null
        ? AvatarConfig.fromJson(pin.avatarConfigJson!)
        : AvatarConfig.defaultConfig();
    final place = pin.placeName?.trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            BlobAvatar(
              mood: moodFromName(pin.currentMood),
              config: config,
              size: 64,
              animate: false,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pin.displayName?.trim().isNotEmpty == true
                        ? pin.displayName!.trim()
                        : 'Friend',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    place != null && place.isNotEmpty
                        ? 'Dropped a receipt at $place'
                        : 'Dropped a receipt nearby',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _relativeTime(pin.occurredAt, DateTime.now()),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
