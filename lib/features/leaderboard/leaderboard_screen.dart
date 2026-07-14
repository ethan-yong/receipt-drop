import 'package:flutter/material.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/badge_hex.dart';
import '../../widgets/blob_avatar.dart';

const _medals = ['🥇', '🥈', '🥉'];

enum _LeaderboardMode { friends, global }

/// Friends + global ranks. Friends uses Postgres RPC/API cache; global uses
/// Redis ZSET via FastAPI when `LEADERBOARD_API_URL` is configured.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  _LeaderboardMode _mode = _LeaderboardMode.friends;
  List<LeaderboardEntry>? _entries;
  BadgeCatalog? _catalog;

  @override
  void initState() {
    super.initState();
    BadgeCatalog.loadBundled().then((c) {
      if (mounted) setState(() => _catalog = c);
    });
    _load();
  }

  Future<void> _load({bool fresh = false}) async {
    setState(() => _entries = null);
    final entries = _mode == _LeaderboardMode.friends
        ? await SocialRepository.getFriendLeaderboard(fresh: fresh)
        : await SocialRepository.getGlobalLeaderboard();
    if (mounted) setState(() => _entries = entries);
  }

  void _setMode(_LeaderboardMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(fresh: _mode == _LeaderboardMode.friends),
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
              _ModeToggle(mode: _mode, onChanged: _setMode),
              const SizedBox(height: AppSpacing.lg),
              if (entries == null)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_mode == _LeaderboardMode.global &&
                  !Env.hasLeaderboardApiConfig)
                const _GlobalApiRequiredNotice()
              else if (entries.isEmpty)
                _EmptyNotice(isGlobal: _mode == _LeaderboardMode.global)
              else ...[
                for (final (i, entry) in entries.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LeaderboardRow(
                      rank: i + 1,
                      entry: entry,
                      catalog: _catalog,
                      isGlobal: _mode == _LeaderboardMode.global,
                    ),
                  ),
                if (_mode == _LeaderboardMode.friends && entries.length <= 1)
                  const _EmptyLeaderboardNotice(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _LeaderboardMode mode;
  final ValueChanged<_LeaderboardMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.divider.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final option in _LeaderboardMode.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: mode == option ? AppColors.cardSurface : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: mode == option
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    option == _LeaderboardMode.friends ? 'Friends' : 'Global',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: mode == option
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                        ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.entry,
    required this.catalog,
    required this.isGlobal,
  });

  final int rank;
  final LeaderboardEntry entry;
  final BadgeCatalog? catalog;
  final bool isGlobal;

  @override
  Widget build(BuildContext context) {
    final config = entry.avatarConfigJson != null
        ? AvatarConfig.fromJson(entry.avatarConfigJson!)
        : AvatarConfig.defaultConfig();
    final mood = moodFromName(entry.currentMood);
    final fallbackName = isGlobal ? 'User' : 'Friend';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: entry.isMe
            ? AppColors.primaryGreen.withValues(alpha: 0.18)
            : AppColors.cardSurface,
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
              rank <= 3 ? _medals[rank - 1] : '$rank',
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
                  entry.isMe ? 'You' : (entry.displayName ?? fallbackName),
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.currentStreak > 0)
                  Text(
                    '🔥 ${entry.currentStreak} days',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (catalog != null && entry.topBadges.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final b in entry.topBadges)
                      if (catalog!.byId(b.badgeId) case final def?)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: BadgeHex(
                            badge: def,
                            earned: true,
                            tier: b.tier,
                            size: 32,
                          ),
                        ),
                  ],
                ),
              Text(
                '${entry.rankScore} pts',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlobalApiRequiredNotice extends StatelessWidget {
  const _GlobalApiRequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        children: [
          const Icon(Icons.public_outlined, size: 40, color: AppColors.textMuted),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Global ranks unavailable',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Set LEADERBOARD_API_URL to view global ranks.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice({required this.isGlobal});

  final bool isGlobal;

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
            isGlobal
                ? 'Log streaks on the home screen to join the global board.'
                : 'Add friends from Settings to start a leaderboard.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
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
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Text(
        'Add friends from Settings to compare ranks.',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}
