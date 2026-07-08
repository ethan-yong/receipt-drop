import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_summary_view_model.dart';

/// Post-OCR receipt confirmation sheet (design handoff Screen 1,
/// `docs/design/design_handoff_receipt_flows/`).
///
/// Lets the user review vendor / total / itemized breakdown before saving:
/// tapping an item's checkbox excludes it (the total recalculates and an
/// Undo banner appears), tapping the pencil renames the vendor inline.
///
/// [show] returns the (possibly edited) draft when the user proceeds via
/// either CTA, or `null` when they cancel or dismiss the sheet.
class ReceiptConfirmSheet extends StatefulWidget {
  const ReceiptConfirmSheet({super.key, required this.draft});

  final ReceiptIngestDraft draft;

  static Future<ReceiptIngestDraft?> show(
    BuildContext context, {
    required ReceiptIngestDraft draft,
  }) {
    return AdaptiveSheet.showForm<ReceiptIngestDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ReceiptSheetColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: ReceiptConfirmSheet(draft: draft),
    );
  }

  @override
  State<ReceiptConfirmSheet> createState() => _ReceiptConfirmSheetState();
}

class _ReceiptConfirmSheetState extends State<ReceiptConfirmSheet> {
  late final List<ReceiptLineItem> _items;
  late final List<bool> _checked;
  late String _vendorName;
  late bool _vendorKnown;
  bool _vendorEdited = false;
  bool _editingVendor = false;
  int? _undoIndex;
  Timer? _undoTimer;
  late final TextEditingController _vendorController;
  final FocusNode _vendorFocus = FocusNode();
  late final bool _hasParsedAmount;
  late final bool _lowConfidence;

  @override
  void initState() {
    super.initState();
    final vm = ReceiptSummaryViewModel.from(widget.draft);
    _items = widget.draft.lineItems;
    _checked = List.filled(_items.length, true);
    _vendorName = vm.merchantDisplay;
    _vendorKnown = widget.draft.merchantRaw?.trim().isNotEmpty ?? false;
    _hasParsedAmount = vm.hasAmount;
    _lowConfidence = vm.isLowConfidence;
    _vendorController = TextEditingController();
    _vendorFocus.addListener(() {
      if (!_vendorFocus.hasFocus && _editingVendor) _commitVendor();
    });
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _vendorController.dispose();
    _vendorFocus.dispose();
    super.dispose();
  }

  /// The parsed receipt total minus every excluded item's price. Starting
  /// from the OCR total (instead of re-summing checked items) keeps tax and
  /// service charge intact when the printed items don't add up to the total.
  double? get _total {
    final base = widget.draft.amountMyr ??
        (_items.isEmpty
            ? null
            : _items.fold<double>(0, (sum, item) => sum + item.priceMyr));
    if (base == null) return null;
    var total = base;
    for (var i = 0; i < _items.length; i++) {
      if (!_checked[i]) total -= _items[i].priceMyr;
    }
    return total < 0 ? 0 : total;
  }

  int get _includedCount => _checked.where((c) => c).length;

  bool get _anyExcluded => _checked.contains(false);

  String get _vendorInitial {
    if (!_vendorKnown && !_vendorEdited) return '?';
    final trimmed = _vendorName.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  void _toggleItem(int index) {
    _undoTimer?.cancel();
    final nowChecked = !_checked[index];
    setState(() {
      _checked[index] = nowChecked;
      if (!nowChecked) {
        _undoIndex = index;
      } else if (_undoIndex == index) {
        _undoIndex = null;
      }
    });
    if (!nowChecked) {
      _undoTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _undoIndex = null);
      });
    }
  }

  void _undoExclude() {
    final index = _undoIndex;
    if (index == null) return;
    _undoTimer?.cancel();
    setState(() {
      _checked[index] = true;
      _undoIndex = null;
    });
  }

  void _startVendorEdit() {
    setState(() {
      _editingVendor = true;
      _vendorController.text = _vendorKnown || _vendorEdited ? _vendorName : '';
      _vendorController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _vendorController.text.length,
      );
    });
  }

  void _commitVendor() {
    final text = _vendorController.text.trim();
    setState(() {
      _editingVendor = false;
      if (text.isNotEmpty && text != _vendorName) {
        _vendorName = text;
        _vendorEdited = true;
      }
    });
  }

  /// The draft with the user's edits applied. Untouched fields pass through
  /// unchanged so a plain "Looks good" behaves exactly like before.
  ReceiptIngestDraft _editedDraft() {
    final total = _total;
    return widget.draft.copyWith(
      merchantRaw: _vendorEdited ? _vendorName : null,
      amountMyr: _anyExcluded ? total : null,
      needsAmount: _anyExcluded && total != null ? false : null,
      lineItems: _anyExcluded
          ? [
              for (var i = 0; i < _items.length; i++)
                if (_checked[i]) _items[i],
            ]
          : null,
    );
  }

  void _proceed() {
    if (_editingVendor) _commitVendor();
    Navigator.pop(context, _editedDraft());
  }

  void _cancel() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final undoIndex = _undoIndex;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CategoryChip(
              category: widget.draft.categoryUser ?? widget.draft.categoryGuess,
            ),
            const Spacer(),
            if (_items.isNotEmpty)
              Text(
                '$_includedCount of ${_items.length} '
                'item${_items.length == 1 ? '' : 's'}',
                style: balooText(
                  13,
                  FontWeight.w600,
                  color: ReceiptSheetColors.subLight,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: ReceiptSheetColors.avatarGold,
                shape: BoxShape.circle,
              ),
              child: Text(
                _vendorInitial,
                style: balooText(18, FontWeight.w800, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _editingVendor ? _vendorField() : _vendorLabel(),
            ),
            const SizedBox(width: 12),
            Material(
              color: ReceiptSheetColors.tile,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _startVendorEdit,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: ReceiptSheetColors.sub,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          total != null ? 'RM ${total.toStringAsFixed(2)}' : '–',
          style: balooText(
            38,
            FontWeight.w800,
            color: total != null
                ? ReceiptSheetColors.ink
                : ReceiptSheetColors.subLight,
            letterSpacing: -0.6,
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 14),
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _ItemRow(
              item: _items[i],
              checked: _checked[i],
              onTap: () => _toggleItem(i),
            ),
          ],
        ],
        if (_lowConfidence) ...[
          const SizedBox(height: 14),
          _NoticeBanner(
            text: widget.draft.needsAmount
                ? "We couldn't read the amount — you can enter it next."
                : "Double-check this amount — we're not fully sure.",
          ),
        ],
      ],
    );

    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (undoIndex != null) ...[
          _UndoBanner(
            itemLabel: _items[undoIndex].displayLabel,
            onUndo: _undoExclude,
          ),
          const SizedBox(height: 14),
        ],
        ReceiptSheetCta(
          label: _hasParsedAmount ? 'Looks good' : 'Edit details',
          onPressed: _proceed,
        ),
        const SizedBox(height: 8),
        if (_hasParsedAmount)
          ReceiptSheetLink(
            label: 'Edit details',
            color: ReceiptSheetColors.link,
            onTap: _proceed,
          ),
        ReceiptSheetLink(
          label: 'Cancel',
          color: ReceiptSheetColors.subLight,
          onTap: _cancel,
        ),
      ],
    );

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ReceiptSheetHandle(),
              const SizedBox(height: 18),
              Flexible(child: SingleChildScrollView(child: body)),
              const SizedBox(height: 20),
              actions,
            ],
          ),
        ),
      ),
    );
  }

  Widget _vendorLabel() {
    return Text(
      _vendorName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: balooText(
        20,
        FontWeight.w800,
        color: ReceiptSheetColors.ink,
        letterSpacing: -0.2,
      ),
    );
  }

  Widget _vendorField() {
    const goldUnderline = UnderlineInputBorder(
      borderSide: BorderSide(color: ReceiptSheetColors.gold, width: 2),
    );
    return TextField(
      controller: _vendorController,
      focusNode: _vendorFocus,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commitVendor(),
      cursorColor: ReceiptSheetColors.gold,
      style: balooText(
        20,
        FontWeight.w800,
        color: ReceiptSheetColors.ink,
        letterSpacing: -0.2,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.only(bottom: 2),
        border: goldUnderline,
        enabledBorder: goldUnderline,
        focusedBorder: goldUnderline,
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  String get _emoji {
    switch (category) {
      case 'Food & Drink':
        return '🍽️';
      case 'Groceries':
        return '🛒';
      case 'Shopping':
        return '🛍️';
      case 'Transport':
        return '🚌';
      default:
        return '🧾';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: ReceiptSheetColors.tile,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Text(
            category,
            style: balooText(
              13,
              FontWeight.w700,
              color: ReceiptSheetColors.sub,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.checked,
    required this.onTap,
  });

  final ReceiptLineItem item;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: checked ? ReceiptSheetColors.gold : Colors.white,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: checked
                    ? ReceiptSheetColors.gold
                    : ReceiptSheetColors.checkboxBorder,
                width: 2,
              ),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: checked ? 1 : 0.4,
              child: Text(
                item.displayLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: balooText(
                  15,
                  FontWeight.w700,
                  decoration: checked ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Opacity(
            opacity: checked ? 1 : 0.4,
            child: Text(item.priceDisplay, style: balooText(15, FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _UndoBanner extends StatelessWidget {
  const _UndoBanner({required this.itemLabel, required this.onUndo});

  final String itemLabel;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ReceiptSheetColors.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$itemLabel excluded',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: balooText(13.5, FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onUndo,
            behavior: HitTestBehavior.opaque,
            child: Text(
              'Undo',
              style: balooText(
                13.5,
                FontWeight.w800,
                color: ReceiptSheetColors.linkStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ReceiptSheetColors.tile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: ReceiptSheetColors.sub,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: balooText(13.5, FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 2,
      width: double.infinity,
      child: CustomPaint(painter: _DashedLinePainter()),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ReceiptSheetColors.dashedDivider
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const dash = 5.0, gap = 5.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      final end = (x + dash) < size.width ? x + dash : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
