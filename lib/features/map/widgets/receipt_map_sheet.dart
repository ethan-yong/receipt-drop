import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/theme/map_sheet_theme.dart';
import '../../../data/repositories/bill_split_repository.dart';
import '../../../data/repositories/places_repository.dart';
import '../../../data/repositories/social_repository.dart';
import '../../../domain/logic/map_aggregates.dart';
import '../../../domain/models/bill_split.dart';
import '../../../domain/models/receipt_line_item.dart';
import '../../../domain/models/transaction_view.dart';
import '../../../widgets/receipt_thumbnail.dart';
import '../../../widgets/skeleton.dart';
import '../../bill_split/person_avatar.dart';

const _signedUrlExpirySeconds = 60 * 60;

/// Google-Maps-style place sheet: a non-modal, draggable sheet living inside
/// the map's Stack (the map stays visible/interactive above it). Replaces
/// `PlaceDetailPanel` — same non-modal `DraggableScrollableSheet`-in-Stack
/// structure and dismiss-on-drag-down behavior, but with a second resting
/// state (collapsed/expanded, matching the Claude Design handoff "Receipt
/// Map Sheet.dc.html"), a receipt-switcher pill row when the place has 2+
/// receipts, a photo carousel (venue photos from Google Places + the
/// receipt's own photo), and a real split-with-friends row.
class ReceiptMapSheet extends StatefulWidget {
  const ReceiptMapSheet({
    super.key,
    required this.cluster,
    required this.controller,
    required this.onClose,
  });

  final MapPlaceCluster cluster;
  final DraggableScrollableController controller;
  final VoidCallback onClose;

  /// Resting extents (fraction of screen height) — matches the handoff's
  /// 312px/680px against its 760px phone-frame mock.
  static const double collapsedExtent = 0.41;
  static const double expandedExtent = 0.89;

  @override
  State<ReceiptMapSheet> createState() => _ReceiptMapSheetState();
}

class _ReceiptMapSheetState extends State<ReceiptMapSheet> {
  bool _closing = false;
  bool _isExpanded = false;
  int _activeIndex = 0;

  List<String> _placePhotoUrls = const [];
  String? _receiptPhotoUrl;
  BillSplitView? _split;
  List<FriendshipView> _friends = const [];
  bool _loadingDetail = true;
  String? _loadedForTxId;

  List<TransactionView> get _receipts {
    final list = [...widget.cluster.transactions]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return list;
  }

  TransactionView get _active {
    final receipts = _receipts;
    final index = _activeIndex.clamp(0, receipts.length - 1);
    return receipts[index];
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onExtentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.controller.isAttached) return;
      widget.controller.animateTo(
        ReceiptMapSheet.collapsedExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
    unawaited(_loadPlacePhotos());
    unawaited(_loadFriends());
    unawaited(_maybeLoadActiveReceiptDetail());
  }

  @override
  void didUpdateWidget(covariant ReceiptMapSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cluster.placeKey != widget.cluster.placeKey) {
      _activeIndex = 0;
      unawaited(_loadPlacePhotos());
      unawaited(_maybeLoadActiveReceiptDetail());
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onExtentChanged);
    super.dispose();
  }

  void _onExtentChanged() {
    if (_closing || !widget.controller.isAttached) return;
    final size = widget.controller.size;
    // Dragged (almost) fully down → dismiss, like Google Maps.
    if (size < 0.08 && size < ReceiptMapSheet.collapsedExtent) {
      _closing = true;
      widget.onClose();
      return;
    }
    final expanded = size >
        (ReceiptMapSheet.collapsedExtent + ReceiptMapSheet.expandedExtent) / 2;
    if (expanded != _isExpanded) {
      setState(() => _isExpanded = expanded);
    }
  }

  Future<void> _loadPlacePhotos() async {
    String? placeId;
    for (final t in widget.cluster.transactions) {
      final id = t.placeGooglePlaceId;
      if (id != null && id.isNotEmpty) {
        placeId = id;
        break;
      }
    }
    if (placeId == null) {
      if (mounted) setState(() => _placePhotoUrls = const []);
      return;
    }
    final urls = await PlacesRepository.fetchPlacePhotos(placeId);
    if (!mounted) return;
    setState(() => _placePhotoUrls = urls);
  }

  Future<void> _loadFriends() async {
    final friends = await SocialRepository.listFriendships();
    if (!mounted) return;
    setState(() => _friends = friends);
  }

  Future<void> _maybeLoadActiveReceiptDetail() async {
    final active = _active;
    if (_loadedForTxId == active.id) return;
    _loadedForTxId = active.id;
    // Direct field write, not setState: this runs synchronously from
    // initState/didUpdateWidget (before/mid the current build, where
    // setState is unsafe) as well as from _selectReceipt's tap handler
    // (which already calls setState itself right before this). Either way
    // a build reading _loadingDetail follows without needing its own
    // trigger here — only the post-await completion below needs setState.
    _loadingDetail = true;
    final results = await Future.wait([
      _resolveReceiptPhotoUrl(active),
      BillSplitRepository.getSplitForTransaction(active.id),
    ]);
    if (!mounted || _loadedForTxId != active.id) return;
    setState(() {
      _receiptPhotoUrl = results[0] as String?;
      _split = results[1] as BillSplitView?;
      _loadingDetail = false;
    });
  }

  Future<String?> _resolveReceiptPhotoUrl(TransactionView tx) async {
    final path = tx.remoteStoragePath;
    if (path == null || path.isEmpty || !Env.hasSupabaseConfig) return null;
    try {
      return await Supabase.instance.client.storage
          .from('receipts')
          .createSignedUrl(path, _signedUrlExpirySeconds);
    } on Object {
      return null;
    }
  }

  void _selectReceipt(int index) {
    if (index == _activeIndex) return;
    setState(() => _activeIndex = index);
    unawaited(_maybeLoadActiveReceiptDetail());
    if (widget.controller.isAttached) {
      widget.controller.animateTo(
        ReceiptMapSheet.collapsedExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);
    final receipts = _receipts;
    final active = _active;
    final split = _split;
    final total = active.amountMyr ?? 0;
    final yourShare = split?.yourShareMyr ?? total;
    final items = active.lineItems ?? const <ReceiptLineItem>[];
    final photoUrls = [
      ..._placePhotoUrls,
      ?_receiptPhotoUrl,
    ];

    return DraggableScrollableSheet(
      controller: widget.controller,
      initialChildSize: 0,
      minChildSize: 0,
      maxChildSize: ReceiptMapSheet.expandedExtent,
      snap: true,
      snapSizes: const [
        ReceiptMapSheet.collapsedExtent,
        ReceiptMapSheet.expandedExtent,
      ],
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: MapSheetColors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kReceiptSheetRadius),
            ),
            boxShadow: [
              BoxShadow(
                color: MapSheetColors.sheetShadow,
                blurRadius: 40,
                offset: const Offset(0, -18),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  margin: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                  decoration: BoxDecoration(
                    color: MapSheetColors.handle,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (receipts.length > 1)
                _ReceiptPillsRow(
                  receipts: receipts,
                  activeIndex: _activeIndex,
                  fmt: fmt,
                  onSelect: _selectReceipt,
                ),
              _PhotoRow(urls: photoUrls, loading: _loadingDetail),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                active.displayPlace,
                                style: balooText(
                                  18,
                                  FontWeight.w800,
                                  color: MapSheetColors.ink,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${dayGroupLabel(active.occurredAt, DateTime.now())} · '
                                '${DateFormat('h:mm a').format(active.occurredAt)}',
                                style: balooText(
                                  12.5,
                                  FontWeight.w600,
                                  color: MapSheetColors.sub,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          fmt.format(yourShare),
                          style: balooText(
                            26,
                            FontWeight.w800,
                            color: MapSheetColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _previewLine(items),
                        style: balooText(
                          13.5,
                          FontWeight.w600,
                          color: MapSheetColors.sub,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _SplitRow(split: split, friends: _friends),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  margin: const EdgeInsets.only(top: 14),
                  height: 1.5,
                  color: MapSheetColors.tile,
                ),
              ),
              if (!_isExpanded)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Swipe up for full receipt',
                        style: balooText(
                          12.5,
                          FontWeight.w700,
                          color: MapSheetColors.subLight,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: MapSheetColors.subLight,
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ITEMS',
                        style: balooText(
                          12,
                          FontWeight.w800,
                          color: MapSheetColors.subLight,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'No items scanned',
                            style: balooText(
                              13,
                              FontWeight.w600,
                              color: MapSheetColors.subLight,
                            ).copyWith(fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        for (final item in items) _ItemRow(item: item),
                      const SizedBox(height: 14),
                      const _DottedDivider(),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: MapSheetColors.tile,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total',
                              style: balooText(
                                15,
                                FontWeight.w800,
                                color: MapSheetColors.ink,
                              ),
                            ),
                            Text(
                              fmt.format(total),
                              style: balooText(
                                20,
                                FontWeight.w800,
                                color: MapSheetColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _previewLine(List<ReceiptLineItem> items) {
    final names = items.map((i) => i.name).toList();
    if (names.length <= 2) return names.join(', ');
    return '${names.take(2).join(', ')} +${names.length - 2} more';
  }
}

class _ReceiptPillsRow extends StatelessWidget {
  const _ReceiptPillsRow({
    required this.receipts,
    required this.activeIndex,
    required this.fmt,
    required this.onSelect,
  });

  final List<TransactionView> receipts;
  final int activeIndex;
  final NumberFormat fmt;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
        children: [
          for (var i = 0; i < receipts.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ReceiptPill(
                label:
                    '${dayGroupLabel(receipts[i].occurredAt, DateTime.now())} · '
                    '${fmt.format(receipts[i].amountMyr ?? 0)}',
                selected: i == activeIndex,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReceiptPill extends StatelessWidget {
  const _ReceiptPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? MapSheetColors.ink : MapSheetColors.tile,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: balooText(
            12.5,
            FontWeight.w700,
            color: selected ? MapSheetColors.surface : MapSheetColors.sub,
          ),
        ),
      ),
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.urls, required this.loading});

  final List<String> urls;

  /// Whether the active receipt's photo is still resolving — shows a
  /// trailing skeleton tile instead of letting a tile pop in abruptly once
  /// the signed URL lands.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty && !loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 0),
        child: ReceiptThumbnail(width: 130, height: 96, radius: 14),
      );
    }
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        children: [
          for (final url in urls)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ReceiptThumbnail(
                imageUrl: url,
                width: 130,
                height: 96,
                radius: 14,
              ),
            ),
          if (loading)
            Skeleton(
              palette: SkeletonPalette.receiptSheet,
              child: SkeletonBox(width: 130, height: 96, radius: 14),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final ReceiptLineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              item.displayLabel,
              style: balooText(15, FontWeight.w700, color: MapSheetColors.body),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.priceDisplay,
            style: balooText(15, FontWeight.w700, color: MapSheetColors.body),
          ),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.split, required this.friends});

  final BillSplitView? split;
  final List<FriendshipView> friends;

  FriendshipView? _friendFor(String userId) {
    for (final f in friends) {
      if (f.otherUserId == userId) return f;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = split;
    if (s == null || s.participants.isEmpty) {
      return Text(
        'Not split — just you',
        style: balooText(12, FontWeight.w600, color: MapSheetColors.sub),
      );
    }
    final n = s.participants.length;
    return Row(
      children: [
        SizedBox(
          height: 22,
          child: Row(
            children: [
              for (final p in s.participants.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: -8),
                  child: PersonAvatar(
                    avatarUrl: _friendFor(p.friendUserId)?.otherAvatarUrl,
                    displayName: _friendFor(p.friendUserId)?.otherDisplayName,
                    userId: p.friendUserId,
                    size: 22,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Split with $n ${n == 1 ? 'friend' : 'friends'}',
          style: balooText(12, FontWeight.w600, color: MapSheetColors.sub),
        ),
      ],
    );
  }
}

/// Dashed divider matching `MapSheetColors.dashedDivider`, above the total
/// tile in the expanded item list — a lightweight `CustomPaint` since there's
/// no existing dashed-line widget in the codebase.
class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(double.infinity, 1),
      painter: _DashedLinePainter(color: MapSheetColors.dashedDivider),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dashWidth = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
