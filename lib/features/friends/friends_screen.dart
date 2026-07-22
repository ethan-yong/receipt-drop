import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/blob_avatar.dart';
import '../../widgets/skeleton.dart';

/// Minimal friends UI — add-by-email plus accept/decline (plan judgment
/// call #10), needed to make the Phase 6 social backend usable at all.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _emailController = TextEditingController();
  List<FriendshipView>? _friendships;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final friendships = await SocialRepository.listFriendships();
    if (mounted) setState(() => _friendships = friendships);
  }

  Future<void> _sendRequest() async {
    final email = _emailController.text;
    setState(() {
      _sending = true;
      _error = null;
    });
    final error = await SocialRepository.requestFriend(email);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _sending = false;
        _error = error;
      });
      return;
    }
    _emailController.clear();
    await _load();
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend request sent')),
    );
  }

  Future<void> _respond(FriendshipView f, bool accept) async {
    await SocialRepository.respondToFriendRequest(f.id, accept);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final friendships = _friendships;
    final incoming =
        friendships?.where((f) => myId != null && f.isIncomingRequestFor(myId)).toList() ??
            const [];
    final accepted =
        friendships?.where((f) => f.status == FriendshipStatus.accepted).toList() ??
            const [];
    final outgoing = friendships
            ?.where(
              (f) => f.status == FriendshipStatus.pending && !incoming.contains(f),
            )
            .toList() ??
        const [];

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Friends'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('Add a friend', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: "Friend's email"),
                    onSubmitted: (_) => _sendRequest(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                FilledButton(
                  onPressed: _sending ? null : _sendRequest,
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.destructive,
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (friendships == null)
              const _FriendshipListSkeleton()
            else ...[
              if (incoming.isNotEmpty) ...[
                Text('Requests', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final f in incoming)
                  _FriendshipTile(
                    friendship: f,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: AppColors.primaryGreen),
                          onPressed: () => _respond(f, true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined, color: AppColors.destructive),
                          onPressed: () => _respond(f, false),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],
              Text('Friends', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (accepted.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    'No friends yet — add one above.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else
                for (final f in accepted) _FriendshipTile(friendship: f),
              if (outgoing.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Sent requests', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final f in outgoing)
                  _FriendshipTile(
                    friendship: f,
                    trailing: Text('Pending', style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _FriendshipListSkeleton extends StatelessWidget {
  const _FriendshipListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 90, height: 16),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            const _FriendshipTileSkeleton(),
          ],
        ],
      ),
    );
  }
}

class _FriendshipTileSkeleton extends StatelessWidget {
  const _FriendshipTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonCircle(size: 40),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: SkeletonBox(width: double.infinity, height: 14)),
      ],
    );
  }
}

class _FriendshipTile extends StatelessWidget {
  const _FriendshipTile({required this.friendship, this.trailing});

  final FriendshipView friendship;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final config = friendship.otherAvatarConfigJson != null
        ? AvatarConfig.fromJson(friendship.otherAvatarConfigJson!)
        : AvatarConfig.defaultConfig();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          BlobAvatar(mood: AvatarMood.balanced, config: config, size: 40, animate: false),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              friendship.otherDisplayName ?? 'Unknown',
              style: Theme.of(context).textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
