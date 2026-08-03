import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/leaderboard_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/badge_catalog.dart';
import '../../domain/models/avatar_config.dart';
import '../../widgets/badge_hex.dart';
import '../../widgets/skeleton.dart';

final _pointsFormat = NumberFormat.decimalPattern();

enum _LeaderboardMode { friends, global }

/// Friends + global ranks. Friends uses Postgres RPC/API cache; global uses
/// Redis ZSET via FastAPI when `LEADERBOARD_API_URL` is configured.
///
/// Visual design from the `Leaderboard.dc.html` handoff (podium for the top
/// 3, hex badges, dark "YOU" row) — the handoff's own "This Week"/"All-Time"
/// tabs were replaced with the app's real Friends/Global tabs, since no
/// week-scoped score exists server-side yet.
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
    final isGlobal = _mode == _LeaderboardMode.global;
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
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    const Text('🏆', style: TextStyle(fontSize: 26)),
                    const SizedBox(height: 2),
                    Text(
                      'Leaderboard',
                      textAlign: TextAlign.center,
                      style: leaderboardText(
                        26,
                        FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isGlobal
                          ? 'See how you stack up worldwide.'
                          : 'See how you stack up against friends.',
                      textAlign: TextAlign.center,
                      style: leaderboardText(
                        14,
                        FontWeight.w600,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ModeToggle(mode: _mode, onChanged: _setMode),
              const SizedBox(height: AppSpacing.lg),
              if (entries == null)
                const _LeaderboardSkeleton()
              else if (isGlobal && !Env.hasLeaderboardApiConfig)
                const _GlobalApiRequiredNotice()
              else if (entries.isEmpty)
                _EmptyNotice(isGlobal: isGlobal)
              else ...[
                if (entries.length >= 3) ...[
                  _Podium(
                    top3: entries.take(3).toList(),
                    catalog: _catalog,
                    isGlobal: isGlobal,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                for (final (i, entry) in entries.indexed)
                  if (entries.length < 3 || i >= 3)
                    _LeaderboardRow(
                      rank: i + 1,
                      entry: entry,
                      catalog: _catalog,
                      isGlobal: isGlobal,
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

/// Deterministic initials-circle color: reuses the entry's own avatar-color
/// pick when available (from `avatarConfigJson`), else a stable pick keyed
/// on user id so the same person always gets the same color.
Color _avatarColorFor(LeaderboardEntry entry) {
  final json = entry.avatarConfigJson;
  if (json != null) {
    return AvatarConfig.fromJson(json).color.swatch;
  }
  final values = AvatarColorOption.values;
  return values[entry.userId.hashCode.abs() % values.length].swatch;
}

String _initialsFor(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final word = parts.first;
    return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
  }
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.name,
    required this.color,
    required this.size,
    required this.fontSize,
  });

  final String name;
  final Color color;
  final double size;
  final double fontSize;

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
        _initialsFor(name),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: textColor,
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
        color: AppColors.creamDark,
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
                    style: leaderboardText(
                      14,
                      FontWeight.w800,
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

class _PodiumConf {
  const _PodiumConf({
    required this.colWidth,
    required this.avatar,
    required this.initialSize,
    required this.nameSize,
    required this.elevate,
    required this.crown,
  });

  final double colWidth;
  final double avatar;
  final double initialSize;
  final double nameSize;
  final double elevate;
  final bool crown;
}

const _podiumConf = {
  1: _PodiumConf(
    colWidth: 104,
    avatar: 84,
    initialSize: 22,
    nameSize: 14,
    elevate: -16,
    crown: true,
  ),
  2: _PodiumConf(
    colWidth: 88,
    avatar: 66,
    initialSize: 17,
    nameSize: 12.5,
    elevate: 6,
    crown: false,
  ),
  3: _PodiumConf(
    colWidth: 88,
    avatar: 66,
    initialSize: 17,
    nameSize: 12.5,
    elevate: 14,
    crown: false,
  ),
};

/// Top-3 spotlight, displayed in 2nd / 1st / 3rd order (winner in the
/// middle), each column elevated/sized per `_podiumConf`.
class _Podium extends StatelessWidget {
  const _Podium({required this.top3, required this.catalog, required this.isGlobal});

  final List<LeaderboardEntry> top3;
  final BadgeCatalog? catalog;
  final bool isGlobal;

  static const _displayOrder = [1, 0, 2];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final i in _displayOrder)
          if (i < top3.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _PodiumColumn(
                rank: i + 1,
                entry: top3[i],
                catalog: catalog,
                isGlobal: isGlobal,
              ),
            ),
      ],
    );
  }
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
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
    final conf = _podiumConf[rank]!;
    final ringColor = badgeTierColor(4 - rank);
    final scoreColor =
        rank == 1 ? leaderboardFirstPlaceScore : AppColors.textPrimary;
    final name = entry.isMe ? 'You' : (entry.displayName ?? (isGlobal ? 'User' : 'Friend'));
    final avatarColor = _avatarColorFor(entry);

    return Transform.translate(
      offset: Offset(0, conf.elevate),
      child: SizedBox(
        width: conf.colWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              child: conf.crown
                  ? const Center(child: Text('👑', style: TextStyle(fontSize: 22)))
                  : null,
            ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: conf.avatar,
                  height: conf.avatar,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(3),
                  child: _InitialsAvatar(
                    name: name,
                    color: avatarColor,
                    size: conf.avatar - 6,
                    fontSize: conf.initialSize,
                  ),
                ),
                Positioned(
                  bottom: -6,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: ringColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.scaffold, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.18),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: leaderboardText(
                conf.nameSize,
                FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_pointsFormat.format(entry.rankScore)} pts',
              textAlign: TextAlign.center,
              style: leaderboardText(12, FontWeight.w800, color: scoreColor),
            ),
            if (catalog != null && entry.topBadges.isNotEmpty) ...[
              const SizedBox(height: 8),
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
                          size: 26,
                          showTierBadge: false,
                        ),
                      ),
                ],
              ),
            ],
          ],
        ),
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
    final fallbackName = isGlobal ? 'User' : 'Friend';
    final name = entry.isMe ? 'You' : (entry.displayName ?? fallbackName);
    final avatarColor = _avatarColorFor(entry);
    final pointsText = _pointsFormat.format(entry.rankScore);

    final badges = [
      if (catalog != null)
        for (final b in entry.topBadges)
          if (catalog!.byId(b.badgeId) case final def?)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: BadgeHex(
                badge: def,
                earned: true,
                tier: b.tier,
                size: entry.isMe ? 22 : 20,
                showTierBadge: false,
              ),
            ),
    ];

    final avatar = _InitialsAvatar(name: name, color: avatarColor, size: 40, fontSize: 13);

    if (entry.isMe) {
      return Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppSpacing.cardBorderRadius,
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withValues(alpha: 0.22),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: leaderboardText(
                  13.5,
                  FontWeight.w800,
                  color: AppColors.insightNeutralOnDark,
                ),
              ),
            ),
            const SizedBox(width: 11),
            avatar,
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          overflow: TextOverflow.ellipsis,
                          style: leaderboardText(14, FontWeight.w800, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'YOU',
                          style: leaderboardText(
                            9,
                            FontWeight.w800,
                            color: AppColors.insightNeutralOnDark,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (badges.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Row(mainAxisSize: MainAxisSize.min, children: badges),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  pointsText,
                  style: leaderboardText(
                    14,
                    FontWeight.w800,
                    color: AppColors.insightNeutralOnDark,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'pts',
                  style: leaderboardText(
                    10,
                    FontWeight.w700,
                    color: AppColors.onDarkCardSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: leaderboardText(
                13.5,
                FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 11),
          avatar,
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: leaderboardText(14, FontWeight.w800),
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Row(mainAxisSize: MainAxisSize.min, children: badges),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pointsText,
                style: leaderboardText(14, FontWeight.w800),
              ),
              const SizedBox(height: 1),
              Text(
                'pts',
                style: leaderboardText(10, FontWeight.w700, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LeaderboardSkeleton extends StatelessWidget {
  const _LeaderboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            const _LeaderboardRowSkeleton(),
          ],
        ],
      ),
    );
  }
}

class _LeaderboardRowSkeleton extends StatelessWidget {
  const _LeaderboardRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 22, height: 22, radius: 4),
          SizedBox(width: 8),
          SkeletonCircle(size: 44),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 110, height: 14),
                SizedBox(height: 6),
                SkeletonBox(width: 70, height: 11),
              ],
            ),
          ),
          SkeletonBox(width: 44, height: 12),
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
            textAlign: TextAlign.center,
            style: leaderboardText(16, FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Set LEADERBOARD_API_URL to view global ranks.',
            textAlign: TextAlign.center,
            style: leaderboardText(14, FontWeight.w600, color: AppColors.textMuted),
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
            textAlign: TextAlign.center,
            style: leaderboardText(16, FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            isGlobal
                ? 'Log streaks on the home screen to join the global board.'
                : 'Add friends from Settings to start a leaderboard.',
            textAlign: TextAlign.center,
            style: leaderboardText(14, FontWeight.w600, color: AppColors.textMuted),
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
        style: leaderboardText(14, FontWeight.w600, color: AppColors.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}
