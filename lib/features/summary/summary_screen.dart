import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/avatar_repository.dart';
import '../../domain/logic/avatar_mood.dart';
import '../../domain/logic/awareness.dart';
import '../../domain/models/avatar_config.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/blob_avatar.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  AvatarConfig? _avatarConfig;

  @override
  void initState() {
    super.initState();
    AvatarRepository.getAvatarConfig().then((config) {
      if (mounted) setState(() => _avatarConfig = config);
    });
  }

  @override
  Widget build(BuildContext context) {
    final avatarConfig = _avatarConfig;
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: StreamBuilder<List<TransactionView>>(
            stream: AppServices.transactions.watchAll(),
            builder: (context, snapshot) {
              final rows = snapshot.data ?? const [];
              final today = todaysTransactions(rows, DateTime.now());
              final mood = deriveAvatarMood(today);
              final summary = awarenessSummary(today);
              final intensity = awarenessIntensity(today);

              return Column(
                children: [
                  Text(
                    "TODAY'S AWARENESS",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 2.4,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (avatarConfig != null)
                    BlobAvatar(mood: mood, config: avatarConfig, size: 140),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.cardSurface,
                      borderRadius: AppSpacing.heroBorderRadius,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.headline,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          summary.sub,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(label: 'Vs. last week', value: intensity),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _StatCard(label: 'Rhythm', value: mood.label),
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => context.goNamed('home'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.heroBorderRadius,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      ),
                      child: Text(
                        'Back home',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: () => context.pushNamed('dashboard'),
                    child: const Text('View full numbers'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: AppSpacing.cardBorderRadius,
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 0.8,
                ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}
