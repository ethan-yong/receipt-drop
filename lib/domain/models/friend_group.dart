/// A group's member, as surfaced by `list_friend_groups()`.
class FriendGroupMember {
  const FriendGroupMember({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final String userId;
  final String? displayName;

  /// Real profile photo URL from `profiles.avatar_url`.
  final String? avatarUrl;
}

/// A named, persisted subset of the caller's accepted friends
/// (`friend_groups` + `friend_group_members`), for one-tap selection in
/// the Bill Split flow.
class FriendGroupView {
  const FriendGroupView({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.members,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final List<FriendGroupMember> members;
}
