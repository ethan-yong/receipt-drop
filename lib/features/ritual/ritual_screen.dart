import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_strip.dart';

enum _RitualPhase { intro, running, done }

/// Full-screen "processing" ritual shown after a receipt is saved, before
/// landing on the Summary/Awareness screen. Simplified from the prototype's
/// multi-item batch animation to a single step — the real flow saves one
/// receipt at a time, unlike the mock's seeded batch of drops.
class RitualScreen extends StatefulWidget {
  const RitualScreen({super.key});

  @override
  State<RitualScreen> createState() => _RitualScreenState();
}

class _RitualScreenState extends State<RitualScreen>
    with SingleTickerProviderStateMixin {
  _RitualPhase _phase = _RitualPhase.intro;
  late final AnimationController _dropController;
  late final Animation<double> _curvedDrop;
  Timer? _introTimer;
  Timer? _doneTimer;

  @override
  void initState() {
    super.initState();
    _dropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _curvedDrop = CurvedAnimation(
      parent: _dropController,
      curve: const Cubic(0.34, 1.56, 0.64, 1),
    );
    _introTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _phase = _RitualPhase.running);
      _dropController.forward(from: 0);
      _doneTimer = Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        setState(() => _phase = _RitualPhase.done);
        Timer(const Duration(milliseconds: 700), () {
          if (mounted) context.goNamed('summary');
        });
      });
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _doneTimer?.cancel();
    _dropController.dispose();
    super.dispose();
  }

  TransactionView? _mostRecent(List<TransactionView> rows) {
    if (rows.isEmpty) return null;
    return rows.reduce(
      (a, b) => a.occurredAt.isAfter(b.occurredAt) ? a : b,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          child: Column(
            children: [
              Column(
                children: [
                  Text(
                    'RITUAL',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 3,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Receipt Drop Machine',
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder<List<TransactionView>>(
                  stream: AppServices.transactions.watchAll(),
                  builder: (context, snapshot) {
                    final tx = _mostRecent(snapshot.data ?? const []);
                    return Center(
                      child: _phase == _RitualPhase.running && tx != null
                          ? AnimatedBuilder(
                              animation: _curvedDrop,
                              builder: (context, child) {
                                final curved = _curvedDrop.value;
                                return Opacity(
                                  opacity: curved.clamp(0.0, 1.0).toDouble(),
                                  child: Transform.translate(
                                    offset: Offset(0, (1 - curved) * -80),
                                    child: child,
                                  ),
                                );
                              },
                              child: ReceiptStrip(
                                impact: tx.effectiveImpactLevel,
                                label: tx.effectiveCategory,
                              ),
                            )
                          : const SizedBox.shrink(),
                    );
                  },
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: AppSpacing.heroBorderRadius,
                  border: Border.all(color: AppColors.divider, width: 2),
                ),
                child: Column(
                  children: [
                    Container(
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 64,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedBuilder(
                          animation: _dropController,
                          builder: (context, _) {
                            final filled = _phase != _RitualPhase.intro;
                            final progress =
                                filled ? _dropController.value : 0.0;
                            return Container(
                              width: 12,
                              height: 6 + 58 * progress,
                              decoration: BoxDecoration(
                                color: filled
                                    ? AppColors.primaryGreen
                                    : AppColors.divider,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      switch (_phase) {
                        _RitualPhase.intro => 'Warming up…',
                        _RitualPhase.running => 'Processing your receipt…',
                        _RitualPhase.done => 'Complete',
                      },
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            letterSpacing: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
