import 'package:flutter/material.dart';

import '../../core/theme/bill_split_theme.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/blob_avatar.dart';

/// A single person's avatar in the Bill Split flow — the real `BlobAvatar`
/// for a friend (their `avatarConfigJson`, mood hardcoded to `balanced`
/// like `_FriendshipTile` in `friends_screen.dart`, since a friend's live
/// mood isn't fetched here), or a plain ink-colored "Y" circle for the
/// payer themselves (no avatar config is loaded for the current user in
/// this flow).
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.isYou,
    this.displayName,
    this.avatarConfigJson,
    this.size = 40,
  });

  final bool isYou;
  final String? displayName;
  final Map<String, dynamic>? avatarConfigJson;
  final double size;

  String get _initials {
    if (isYou) return 'Y';
    final name = displayName?.trim();
    if (name == null || name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (isYou) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: BillSplitColors.ink,
        child: Text(
          _initials,
          style: balooText(size * 0.35, FontWeight.w800, color: Colors.white),
        ),
      );
    }
    final config = avatarConfigJson != null
        ? AvatarConfig.fromJson(avatarConfigJson!)
        : AvatarConfig.defaultConfig();
    return BlobAvatar(
      mood: AvatarMood.balanced,
      config: config,
      size: size,
      animate: false,
    );
  }
}
