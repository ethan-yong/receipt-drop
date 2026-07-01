import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/models/avatar_config.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/pixel_avatar.dart';

enum _Tab { color, eyes, hat }

class AvatarCustomizerScreen extends StatefulWidget {
  const AvatarCustomizerScreen({super.key});

  @override
  State<AvatarCustomizerScreen> createState() =>
      _AvatarCustomizerScreenState();
}

class _AvatarCustomizerScreenState extends State<AvatarCustomizerScreen> {
  AvatarConfig? _draft;
  _Tab _tab = _Tab.color;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await AvatarRepository.getAvatarConfig();
    if (mounted) setState(() => _draft = config);
  }

  void _update(AvatarConfig Function(AvatarConfig) updater) {
    final current = _draft;
    if (current == null) return;
    setState(() => _draft = updater(current));
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    await AvatarRepository.saveAvatarConfig(draft);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: draft == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _RoundIconButton(
                          icon: Icons.arrow_back,
                          onTap: () => context.pop(),
                        ),
                        Text(
                          'Customize',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        _RoundIconButton(
                          icon: Icons.check,
                          filled: true,
                          onTap: _saving ? null : _save,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFBF6E8), Color(0xFFF2EAD3)],
                          ),
                          borderRadius: AppSpacing.heroBorderRadius,
                        ),
                        child: Center(
                          child: StreamBuilder<List<TransactionView>>(
                            stream: AppServices.transactions.watchAll(),
                            builder: (context, snapshot) {
                              final rows = snapshot.data ?? const [];
                              final mood = deriveAvatarMood(
                                todaysTransactions(rows, DateTime.now()),
                              );
                              return PixelAvatar(
                                mood: mood,
                                config: draft,
                                size: 220,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      0,
                    ),
                    child: SegmentedButton<_Tab>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: _Tab.color, label: Text('COLOR')),
                        ButtonSegment(value: _Tab.eyes, label: Text('EYES')),
                        ButtonSegment(value: _Tab.hat, label: Text('HAT')),
                      ],
                      selected: {_tab},
                      onSelectionChanged: (selection) =>
                          setState(() => _tab = selection.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: AppColors.cardSurface,
                        foregroundColor: AppColors.textSecondary,
                        selectedBackgroundColor: AppColors.textPrimary,
                        selectedForegroundColor: AppColors.scaffold,
                        side: const BorderSide(color: AppColors.divider),
                        textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.lg,
                      ),
                      child: switch (_tab) {
                        _Tab.color => _ColorGrid(draft: draft, onPick: (c) => _update((d) => d.copyWith(color: c))),
                        _Tab.eyes => _EyesGrid(draft: draft, onPick: (e) => _update((d) => d.copyWith(eyes: e))),
                        _Tab.hat => _HatGrid(draft: draft, onPick: (h) => _update((d) => d.copyWith(hat: h))),
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.primaryGreen : AppColors.cardSurface,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: AppColors.divider),
        ),
        child: Icon(icon, size: 20, color: AppColors.textPrimary),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.selected,
    required this.onTap,
    required this.preview,
    required this.label,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget preview;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.cardBorderRadius,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: AppSpacing.cardBorderRadius,
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(child: Center(child: preview)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorGrid extends StatelessWidget {
  const _ColorGrid({required this.draft, required this.onPick});

  final AvatarConfig draft;
  final void Function(AvatarColorOption) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (final c in AvatarColorOption.values)
          _OptionTile(
            selected: draft.color == c,
            onTap: () => onPick(c),
            label: c.label,
            preview: PixelAvatar(
              mood: AvatarMood.calm,
              config: AvatarConfig(
                color: c,
                eyes: AvatarEyesOption.neutral,
                hat: AvatarHatOption.none,
              ),
              size: 64,
              animate: false,
            ),
          ),
      ],
    );
  }
}

class _EyesGrid extends StatelessWidget {
  const _EyesGrid({required this.draft, required this.onPick});

  final AvatarConfig draft;
  final void Function(AvatarEyesOption) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (final e in AvatarEyesOption.values)
          _OptionTile(
            selected: draft.eyes == e,
            onTap: () => onPick(e),
            label: e.label,
            preview: PixelAvatar(
              mood: AvatarMood.calm,
              config: AvatarConfig(
                color: draft.color,
                eyes: e,
                hat: AvatarHatOption.none,
              ),
              size: 64,
              animate: false,
            ),
          ),
      ],
    );
  }
}

class _HatGrid extends StatelessWidget {
  const _HatGrid({required this.draft, required this.onPick});

  final AvatarConfig draft;
  final void Function(AvatarHatOption) onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      children: [
        for (final h in AvatarHatOption.values)
          _OptionTile(
            selected: draft.hat == h,
            onTap: () => onPick(h),
            label: h.label,
            preview: PixelAvatar(
              mood: AvatarMood.calm,
              config: AvatarConfig(
                color: draft.color,
                eyes: AvatarEyesOption.neutral,
                hat: h,
              ),
              size: 64,
              animate: false,
            ),
          ),
      ],
    );
  }
}
