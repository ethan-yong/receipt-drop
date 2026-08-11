import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../domain/models/pending_import_model.dart';
import '../../domain/models/transaction_view.dart';
import '../../widgets/skeleton.dart';
import '../share/batch_scan_progress.dart';
import 'pending_import_service.dart';

/// Palette for this screen only, matching the Claude Design handoff
/// (`Receipts Waiting.dc.html`) — a warmer/darker cream+ink pairing than
/// `ReceiptSheetColors` (which is documented as specific to the confirm
/// sheet/location picker), so kept local rather than forced onto shared
/// tokens that don't actually match these hex values.
abstract final class _PendingWaitingColors {
  static const screenBg = Color(0xFFFCF6EA);
  static const cardBg = Colors.white;
  static const ink = Color(0xFF23201A);
  static const groupLabel = Color(0xFFB0A895);
  static const meta = Color(0xFF9A9284);
  static const pulseDot = Color(0xFFE2885C);
  static const gold = Color(0xFFF6C64B);

  /// `rgba(220,170,40,.4)` — glow under the "Process all" bar.
  static const goldShadow = Color(0x66DCAA28);

  /// `rgba(60,50,20,.08)` — soft shadow under each card.
  static const cardShadow = Color(0x143C3214);
}

class PendingImportsScreen extends StatefulWidget {
  const PendingImportsScreen({super.key});

  @override
  State<PendingImportsScreen> createState() => _PendingImportsScreenState();
}

class _PendingImportsScreenState extends State<PendingImportsScreen> {
  @override
  void initState() {
    super.initState();
    // Heal cards stuck on the spinner after system-back / process kill —
    // `processing` is only valid while processImport owns the UI.
    unawaited(AppServices.pendingImports.resetAbandonedProcessing());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PendingWaitingColors.screenBg,
      appBar: AppBar(
        backgroundColor: _PendingWaitingColors.screenBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: _PendingWaitingColors.ink),
        title: Text(
          'Receipts Waiting',
          style: balooText(
            21,
            FontWeight.w800,
            color: _PendingWaitingColors.ink,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: StreamBuilder<List<PendingImportModel>>(
        stream: AppServices.pendingImports.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _PendingImportsSkeleton();
          }

          final imports = snapshot.data ?? const [];
          if (imports.isEmpty) {
            return _EmptyState();
          }

          final groups = _groupByDay(imports);
          final processable =
              imports.where((i) => i.status == 'local').toList();

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  itemCount: groups.length,
                  itemBuilder: (context, index) =>
                      _DayGroupSection(group: groups[index]),
                ),
              ),
              if (processable.length > 1)
                _ProcessAllBar(
                  count: processable.length,
                  onTap: () => _processAll(context, processable),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processAll(
    BuildContext context,
    List<PendingImportModel> imports,
  ) async {
    var progress = BatchScanProgress(totalCount: imports.length);
    final savedTxs = <TransactionView>[];
    for (final import in imports) {
      if (!context.mounted) return;
      final result = await PendingImportService.processImport(
        context,
        import,
        batchProgress: progress,
        deferSaveSuccessNav: true,
      );
      progress = result.progress ?? progress;
      if (result.savedTx != null) savedTxs.add(result.savedTx!);
    }
    if (savedTxs.isNotEmpty && context.mounted) {
      context.pushNamed('save-success', extra: savedTxs);
    }
  }
}

/// One calendar-day bucket of pending imports, most-recent day first —
/// mirrors the design's grouped list (`groups` in the handoff's mock data).
class _DayGroup {
  _DayGroup(this.label, this.items);

  final String label;
  final List<PendingImportModel> items;
}

/// Groups already-desc-sorted [imports] (per `PendingImportsRepository
/// .watchAll()`'s `ORDER BY created_at DESC`) into contiguous same-day
/// buckets without re-sorting.
List<_DayGroup> _groupByDay(List<PendingImportModel> imports) {
  final groups = <_DayGroup>[];
  for (final import in imports) {
    final label = _dayLabel(import.createdAt);
    if (groups.isNotEmpty && groups.last.label == label) {
      groups.last.items.add(import);
    } else {
      groups.add(_DayGroup(label, [import]));
    }
  }
  return groups;
}

/// "Today" for the device's current calendar day, else "d/M" (matches the
/// handoff's "29/7" style — no year, no month name).
String _dayLabel(DateTime createdAt) {
  final local = createdAt.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return isToday ? 'Today' : DateFormat('d/M').format(local);
}

class _DayGroupSection extends StatelessWidget {
  const _DayGroupSection({required this.group});

  final _DayGroup group;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.label.toUpperCase(),
            style: balooText(
              12,
              FontWeight.w800,
              color: _PendingWaitingColors.groupLabel,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < group.items.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _PendingImportCard(
              import: group.items[i],
              onProcess: () => PendingImportService.processImport(
                context,
                group.items[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessAllBar extends StatelessWidget {
  const _ProcessAllBar({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: _PendingWaitingColors.gold,
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              color: _PendingWaitingColors.goldShadow,
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Center(
              child: Text(
                'Process all ($count)',
                style: balooText(
                  16,
                  FontWeight.w800,
                  color: _PendingWaitingColors.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingImportsSkeleton extends StatelessWidget {
  const _PendingImportsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        children: const [
          SkeletonBox(width: 60, height: 12, radius: 6),
          SizedBox(height: 12),
          _PendingImportCardSkeleton(),
          SizedBox(height: 12),
          _PendingImportCardSkeleton(),
          SizedBox(height: 12),
          _PendingImportCardSkeleton(),
        ],
      ),
    );
  }
}

class _PendingImportCardSkeleton extends StatelessWidget {
  const _PendingImportCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _PendingWaitingColors.cardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: SkeletonCircle(size: 8),
          ),
          const SizedBox(width: 9),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130, height: 16, radius: 6),
                SizedBox(height: 6),
                SkeletonBox(width: 90, height: 12, radius: 6),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SkeletonBox(
            width: 72,
            height: 32,
            radius: AppSpacing.chipRadius,
          ),
        ],
      ),
    );
  }
}

class _PendingImportCard extends StatelessWidget {
  const _PendingImportCard({
    required this.import,
    required this.onProcess,
  });

  final PendingImportModel import;
  final VoidCallback onProcess;

  /// Best-effort resolved venue name, or a generic fallback — the design's
  /// mock data always has a location, but real shares often won't (no
  /// permission, no fix, no nearby match — see
  /// `docs/plans/2026-07-30-pending-receipt-location-context.md`).
  String get _title {
    final venue = import.venueLabel?.trim();
    return (venue != null && venue.isNotEmpty) ? venue : 'Receipt';
  }

  /// Time + (if known) source app + (if attached) note, joined the same way
  /// as the handoff's `meta` field.
  String get _meta {
    final source = import.sourceApp?.trim();
    final note = import.note?.trim();
    final parts = <String>[
      DateFormat('h:mm a').format(import.createdAt.toLocal()),
      if (source != null && source.isNotEmpty) 'via $source',
      if (note != null && note.isNotEmpty) note,
    ];
    return parts.join('  ·  ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _PendingWaitingColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: _PendingWaitingColors.cardShadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: import.isFailed
                ? const _StaticDot(color: AppColors.destructive)
                : import.isProcessing
                    ? const _StaticDot(color: _PendingWaitingColors.pulseDot)
                    : const _PulsingDot(),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: balooText(
                    16,
                    FontWeight.w800,
                    color: _PendingWaitingColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  import.isFailed ? 'Could not read — tap Retry' : _meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: balooText(
                    12.5,
                    FontWeight.w600,
                    color: import.isFailed
                        ? AppColors.destructive
                        : _PendingWaitingColors.meta,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (import.isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _ProcessPill(
              label: import.isFailed ? 'Retry' : 'Process',
              destructive: import.isFailed,
              onTap: onProcess,
            ),
        ],
      ),
    );
  }
}

class _ProcessPill extends StatelessWidget {
  const _ProcessPill({
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final background =
        destructive ? AppColors.destructive : _PendingWaitingColors.gold;
    final foreground = destructive ? Colors.white : _PendingWaitingColors.ink;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            label,
            style: balooText(13, FontWeight.w800, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// Plain, non-animated dot — used for the failed/processing states, where a
/// pulsing "still waiting" affordance would be misleading.
class _StaticDot extends StatelessWidget {
  const _StaticDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Breathing dot for a not-yet-processed import — mirrors the handoff's
/// `pendingPulse` keyframe (opacity 0.35 -> 1 -> 0.35, 1.4s, ease-in-out).
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ).drive(Tween(begin: 0.35, end: 1.0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: const _StaticDot(color: _PendingWaitingColors.pulseDot),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 64,
              color: _PendingWaitingColors.groupLabel,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No receipts waiting',
              style: balooText(
                17,
                FontWeight.w800,
                color: _PendingWaitingColors.ink,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Share a receipt from any app and it will appear here',
              textAlign: TextAlign.center,
              style: balooText(
                13,
                FontWeight.w600,
                color: _PendingWaitingColors.meta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
