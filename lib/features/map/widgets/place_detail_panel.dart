import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/logic/dashboard_aggregates.dart';
import '../../../domain/models/transaction_view.dart';

/// Google-Maps-style place panel: a non-modal sheet living inside the map's
/// Stack. It slides up to half the screen (the map stays visible and
/// interactive above it), lists each scanned receipt at the place with its
/// vendor and line items, and dismisses when dragged down.
class PlaceDetailPanel extends StatefulWidget {
  const PlaceDetailPanel({
    super.key,
    required this.cluster,
    required this.controller,
    required this.onClose,
  });

  final MapPlaceCluster cluster;
  final DraggableScrollableController controller;
  final VoidCallback onClose;

  /// The panel's resting extent (fraction of screen height).
  static const double halfExtent = 0.5;

  @override
  State<PlaceDetailPanel> createState() => _PlaceDetailPanelState();
}

class _PlaceDetailPanelState extends State<PlaceDetailPanel> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExtentChanged);
    // Slide up from the bottom edge — the Google-Maps open animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.isAttached) return;
      widget.controller.animateTo(
        PlaceDetailPanel.halfExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExtentChanged);
    super.dispose();
  }

  void _onExtentChanged() {
    if (_closing || !widget.controller.isAttached) return;
    // Dragged (almost) fully down → dismiss, like Google Maps.
    if (widget.controller.size < 0.08 &&
        widget.controller.size < PlaceDetailPanel.halfExtent) {
      _closing = true;
      widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);
    final transactions = [...widget.cluster.transactions]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: 0,
      minChildSize: 0,
      maxChildSize: PlaceDetailPanel.halfExtent,
      snap: true,
      snapSizes: const [PlaceDetailPanel.halfExtent],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppSpacing.heroRadius),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.cluster.displayName,
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${fmt.format(widget.cluster.totalSpend)} · '
                            '${widget.cluster.visitCount} '
                            '${widget.cluster.visitCount == 1 ? 'visit' : 'visits'}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    // Google-Maps-style close chip.
                    Material(
                      color: AppColors.scaffold,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: widget.onClose,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              for (var i = 0; i < transactions.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    indent: AppSpacing.md,
                    endIndent: AppSpacing.md,
                  ),
                _ReceiptSection(transaction: transactions[i], fmt: fmt),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

/// One scanned receipt at this place: vendor header (tappable → tx detail)
/// followed by its line items.
class _ReceiptSection extends StatelessWidget {
  const _ReceiptSection({required this.transaction, required this.fmt});

  final TransactionView transaction;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final tx = transaction;
    final items = tx.lineItems ?? const [];
    final vendor = tx.merchantRaw?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              context.pushNamed('tx-detail', pathParameters: {'id': tx.id}),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.scaffold,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🧾', style: TextStyle(fontSize: 17)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor != null && vendor.isNotEmpty
                            ? vendor
                            : 'Receipt',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        dayGroupLabel(tx.occurredAt, DateTime.now()),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (tx.amountMyr != null)
                  Text(
                    fmt.format(tx.amountMyr),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.md + 46,
              right: AppSpacing.md,
              bottom: AppSpacing.sm + 2,
            ),
            child: Text(
              'No items scanned',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.textMuted,
              ),
            ),
          )
        else
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md + 46,
                right: AppSpacing.md,
                bottom: AppSpacing.xs + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.quantity != null && item.quantity! > 1
                          ? '${item.quantity} × ${item.name}'
                          : item.name,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'RM ${item.priceMyr.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}
