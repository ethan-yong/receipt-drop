import 'package:flutter/material.dart';

import '../core/theme/receipt_sheet_theme.dart';
import '../domain/models/receipt_line_item.dart';
import '../features/bill_split/person_avatar.dart';

/// One receipt line, left → right: name | assignee avatar(s) | quantity | price.
/// Used by the map pin sheet and the Transaction detail screen.
///
/// When [onEditName] / [onEditPrice] / [onEditQuantity] are null the row is
/// read-only (map sheet). When callbacks are provided, tapping opens inline
/// edit or the quantity picker (Transaction detail).
class ReceiptLineItemRow extends StatelessWidget {
  const ReceiptLineItemRow({
    super.key,
    required this.item,
    required this.assigneeIds,
    required this.displayNameFor,
    required this.avatarUrlFor,
    required this.textStyle,
    this.bottomPadding = 14,
    this.editingName = false,
    this.editingPrice = false,
    this.nameController,
    this.nameFocus,
    this.priceController,
    this.priceFocus,
    this.nameFieldKey,
    this.priceFieldKey,
    this.onEditName,
    this.onEditPrice,
    this.onEditQuantity,
  });

  final ReceiptLineItem item;
  final List<String> assigneeIds;
  final String? Function(String userId) displayNameFor;
  final String? Function(String userId) avatarUrlFor;
  final TextStyle textStyle;

  /// Vertical gap under the row (map sheet uses 14; tx detail uses 6).
  final double bottomPadding;

  final bool editingName;
  final bool editingPrice;
  final TextEditingController? nameController;
  final FocusNode? nameFocus;
  final TextEditingController? priceController;
  final FocusNode? priceFocus;
  final Key? nameFieldKey;
  final Key? priceFieldKey;
  final VoidCallback? onEditName;
  final VoidCallback? onEditPrice;
  final VoidCallback? onEditQuantity;

  /// Up to 3 avatars + optional "+N" chip (22 + 3×10).
  static const avatarColW = 52.0;
  /// Fits "x99" with a little room; keeps qty digits column-aligned.
  static const qtyColW = 34.0;
  /// Fits typical "RM 999.99"; right-aligned so uneven digit counts line up.
  static const priceColW = 80.0;
  static const avatarSize = 22.0;
  static const _maxVisibleAvatars = 3;
  static const _avatarOverlapStep = 10.0;

  @override
  Widget build(BuildContext context) {
    final qty = item.quantity ?? 1;
    // Always prefix with x (x1, x3, …) — never bare "1" or trailing "3x".
    final qtyLabel = 'x$qty';
    final shown = assigneeIds.take(_maxVisibleAvatars).toList();
    final overflow = assigneeIds.length - shown.length;

    final qtyWidget = onEditQuantity == null
        ? Text(
            qtyLabel,
            style: textStyle,
            maxLines: 1,
            textAlign: TextAlign.right,
          )
        : GestureDetector(
            onTap: onEditQuantity,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              height: 28,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(qtyLabel, style: textStyle, maxLines: 1),
              ),
            ),
          );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        children: [
          Expanded(
            child: editingName ? _nameField() : _nameLabel(),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: avatarColW,
            height: avatarSize,
            child: shown.isEmpty
                ? null
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Positioned(
                          left: i * _avatarOverlapStep,
                          child: PersonAvatar(
                            avatarUrl: avatarUrlFor(shown[i]),
                            displayName: displayNameFor(shown[i]),
                            userId: shown[i],
                            size: avatarSize,
                          ),
                        ),
                      if (overflow > 0)
                        Positioned(
                          left: shown.length * _avatarOverlapStep,
                          child: _OverflowChip(
                            count: overflow,
                            size: avatarSize,
                            textStyle: textStyle,
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: qtyColW, child: qtyWidget),
          const SizedBox(width: 8),
          SizedBox(
            width: priceColW,
            child: Align(
              alignment: Alignment.centerRight,
              child: editingPrice ? _priceField() : _priceLabel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nameLabel() {
    final label = Text(
      item.name,
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (onEditName == null) return label;
    return GestureDetector(
      onTap: onEditName,
      behavior: HitTestBehavior.opaque,
      child: label,
    );
  }

  Widget _nameField() {
    final controller = nameController;
    final focus = nameFocus;
    if (controller == null || focus == null) return _nameLabel();
    final field = TextField(
      key: const Key('receipt-item-name-field'),
      controller: controller,
      focusNode: focus,
      autofocus: true,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => focus.unfocus(),
      cursorColor: ReceiptSheetColors.gold,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: textStyle.copyWith(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: ReceiptSheetColors.tile,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ReceiptSheetColors.gold, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ReceiptSheetColors.gold, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: ReceiptSheetColors.gold, width: 1.5),
        ),
      ),
    );
    if (nameFieldKey == null) return field;
    return KeyedSubtree(key: nameFieldKey, child: field);
  }

  Widget _priceLabel() {
    final label = Text(
      item.priceDisplay,
      style: textStyle,
      maxLines: 1,
      textAlign: TextAlign.right,
    );
    if (onEditPrice == null) return label;
    return GestureDetector(
      onTap: onEditPrice,
      behavior: HitTestBehavior.opaque,
      child: label,
    );
  }

  Widget _priceField() {
    final controller = priceController;
    final focus = priceFocus;
    if (controller == null || focus == null) return _priceLabel();
    const goldUnderline = UnderlineInputBorder(
      borderSide: BorderSide(color: ReceiptSheetColors.gold, width: 2),
    );
    final field = TextField(
      key: const Key('receipt-price-field'),
      controller: controller,
      focusNode: focus,
      autofocus: true,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => focus.unfocus(),
      cursorColor: ReceiptSheetColors.gold,
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: textStyle.copyWith(fontWeight: FontWeight.w700),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        prefixText: 'RM ',
        contentPadding: EdgeInsets.only(bottom: 2),
        border: goldUnderline,
        enabledBorder: goldUnderline,
        focusedBorder: goldUnderline,
      ),
    );
    if (priceFieldKey == null) return field;
    return KeyedSubtree(key: priceFieldKey, child: field);
  }
}

/// Circular "+N" chip when more than 3 people share a line item.
class _OverflowChip extends StatelessWidget {
  const _OverflowChip({
    required this.count,
    required this.size,
    required this.textStyle,
  });

  final int count;
  final double size;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ReceiptSheetColors.tile,
        shape: BoxShape.circle,
        border: Border.all(color: ReceiptSheetColors.surface, width: 1.5),
      ),
      child: Text(
        '+$count',
        style: textStyle.copyWith(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          height: 1,
          color: ReceiptSheetColors.sub,
        ),
      ),
    );
  }
}
