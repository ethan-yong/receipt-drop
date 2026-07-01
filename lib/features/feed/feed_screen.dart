import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/blob_avatar.dart';
import '../../widgets/reaction_chip.dart';

/// Port of Impact Drops' feed.tsx — friends' auto-generated drop lines,
/// backed by `SocialRepository.getFriendFeed()` (the `get_friend_feed()`
/// security-definer function).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<FeedPost>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final posts = await SocialRepository.getFriendFeed();
    if (mounted) setState(() => _posts = posts);
  }

  void _react(int index, String kind) {
    final post = _posts![index];
    SocialRepository.reactToPost(post.postId, kind);
    setState(() {
      _posts![index] = switch (kind) {
        'fire' => post.copyWith(fireCount: post.fireCount + 1),
        'laugh' => post.copyWith(laughCount: post.laughCount + 1),
        _ => post.copyWith(eyesCount: post.eyesCount + 1),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xl,
            ),
            children: [
              Text('Feed', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text(
                'What friends are dropping.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (posts == null)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (posts.isEmpty)
                const _EmptyFeedNotice()
              else
                for (final (i, post) in posts.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _FeedPostCard(
                      post: post,
                      onReact: (kind) => _react(i, kind),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({required this.post, required this.onReact});

  final FeedPost post;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final config = post.avatarConfigJson != null
        ? AvatarConfig.fromJson(post.avatarConfigJson!)
        : AvatarConfig.defaultConfig();
    final mood = moodFromName(post.currentMood);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlobAvatar(mood: mood, config: config, size: 48, animate: false),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        post.displayName ?? 'Friend',
                        style: Theme.of(context).textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(post.createdAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(post.line, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    ReactionChip(
                      emoji: '🔥',
                      count: post.fireCount,
                      onTap: () => onReact('fire'),
                    ),
                    const SizedBox(width: 8),
                    ReactionChip(
                      emoji: '😂',
                      count: post.laughCount,
                      onTap: () => onReact('laugh'),
                    ),
                    const SizedBox(width: 8),
                    ReactionChip(
                      emoji: '👀',
                      count: post.eyesCount,
                      onTap: () => onReact('eyes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeedNotice extends StatelessWidget {
  const _EmptyFeedNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.people_outline, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No drops from friends yet',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Add friends from Settings to see their activity here.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}
