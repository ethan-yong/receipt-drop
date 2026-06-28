import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/receipt_strip.dart';

enum _RitualPhase { intro, running, done }

/// Batch ritual for all unritualled drops since the last run.
class RitualScreen extends StatefulWidget {
  const RitualScreen({super.key});

  @override
  State<RitualScreen> createState() => _RitualScreenState();
}

class _RitualScreenState extends State<RitualScreen>
    with SingleTickerProviderStateMixin {
  _RitualPhase _phase = _RitualPhase.intro;
  List<TransactionView> _queue = const [];
  int _currentIndex = 0;
  late final AnimationController _dropController;
  late final Animation<double> _curvedDrop;
  StreamSubscription<List<TransactionView>>? _queueSub;
  Timer? _introTimer;
  Timer? _stepTimer;
  var _started = false;

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
    _queueSub = AppServices.transactions.watchUnritualled().listen(_onQueue);
  }

  void _onQueue(List<TransactionView> rows) {
    if (!mounted || _started) return;
    if (rows.isEmpty) {
      context.goNamed('summary');
      return;
    }
    _started = true;
    setState(() => _queue = rows);
    _introTimer = Timer(const Duration(milliseconds: 900), _beginRunning);
  }

  void _beginRunning() {
    if (!mounted || _queue.isEmpty) return;
    setState(() {
      _phase = _RitualPhase.running;
      _currentIndex = 0;
    });
    _animateCurrentDrop();
  }

  void _animateCurrentDrop() {
    _dropController.forward(from: 0);
    _stepTimer?.cancel();
    _stepTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      if (_currentIndex + 1 < _queue.length) {
        setState(() => _currentIndex++);
        _animateCurrentDrop();
      } else {
        _finish();
      }
    });
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _phase = _RitualPhase.done);
    await AppServices.transactions
        .markAsRitualled(_queue.map((t) => t.id).toList());
    _stepTimer?.cancel();
    _stepTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) context.goNamed('summary');
    });
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _introTimer?.cancel();
    _stepTimer?.cancel();
    _dropController.dispose();
    super.dispose();
  }

  TransactionView? get _currentTx =>
      _currentIndex < _queue.length ? _queue[_currentIndex] : null;

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
                  if (_queue.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        _phase == _RitualPhase.running
                            ? '${_currentIndex + 1} of ${_queue.length}'
                            : '${_queue.length} drop${_queue.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Center(
                  child: _phase == _RitualPhase.running && _currentTx != null
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
                            impact: _currentTx!.effectiveImpactLevel,
                            label: _currentTx!.effectiveCategory,
                          ),
                        )
                      : const SizedBox.shrink(),
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
