import 'package:flutter/material.dart';

import '../../widgets/profile_photo.dart';

/// A single person's avatar in the Bill Split flow — the real profile photo
/// from `profiles.avatar_url` (set at `/profile-setup` / Settings), with
/// initials fallback via [ProfilePhoto]. No stylized blob / dart avatar.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    this.avatarUrl,
    this.displayName,
    this.userId,
    this.size = 40,
  });

  final String? avatarUrl;
  final String? displayName;
  final String? userId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ProfilePhoto(
      size: size,
      avatarUrl: avatarUrl,
      displayName: displayName,
      userId: userId,
    );
  }
}
