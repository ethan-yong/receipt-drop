import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/leaderboard_label.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/blob_avatar.dart';

const _medals = ['🥇', '🥈', '🥉'];

/// Port of Impact Drops' leaderboard.tsx, Friends-only (the prototype's
/// "Uni Group" toggle is dropped — no cohort/group concept exists in this
/// app; see plan judgment call #7). Ranked by `get_friend_leaderboard()`:
/// current daily-logging streak, then earned-badge count.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<LeaderboardEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await SocialRepository.getFriendLeaderboard();
    if (mounted) setState(() => _entries = entries);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
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
              Text('Ranks', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 4),
              Text(
                'Consistency over amounts.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (entries == null)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                for (final (i, entry) in entries.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LeaderboardRow(rank: i + 1, entry: entry),
                  ),
                // get_friend_leaderboard() always includes the caller, so an
                // empty list only happens when signed out; "just me" means
                // no accepted friends yet.
                if (entries.length <= 1) const _EmptyLeaderboardNotice(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final config = entry.avatarConfigJson != null
        ? AvatarConfig.fromJson(entry.avatarConfigJson!)
        : AvatarConfig.defaultConfig();
    final mood = moodFromName(entry.currentMood);
    final label = leaderboardLabel(mood: mood, streak: entry.currentStreak);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: entry.isMe ? AppColors.primaryGreen.withValues(alpha: 0.18) : AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(
          color: entry.isMe ? AppColors.primaryGreen : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(width: 8),
          BlobAvatar(mood: mood, config: config, size: 44, animate: false),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.isMe ? 'You' : (entry.displayName ?? 'Friend'),
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(label, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (rank <= 3) Text(_medals[rank - 1], style: const TextStyle(fontSize: 20)),
        ],
      ),
    );
  }
}

class _EmptyLeaderboardNotice extends StatelessWidget {
  const _EmptyLeaderboardNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.emoji_events_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No ranks yet',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Add friends from Settings to start a leaderboard.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
