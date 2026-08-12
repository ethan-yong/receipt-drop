import 'package:flutter/cupertino.dart';

import '../core/theme/receipt_sheet_theme.dart';
import 'receipt_sheet_widgets.dart';

/// Bottom-sheet wheel picker for correcting a receipt line-item quantity.
/// Returns the selected int via [Navigator.pop] on Done; dismiss/scrim returns
/// null so the caller leaves the original quantity unchanged.
class QuantityPickerSheet extends StatefulWidget {
  const QuantityPickerSheet({
    super.key,
    required this.itemName,
    required this.initialQuantity,
  });

  final String itemName;
  final int initialQuantity;

  @override
  State<QuantityPickerSheet> createState() => _QuantityPickerSheetState();
}

class _QuantityPickerSheetState extends State<QuantityPickerSheet> {
  /// Dynamic upper bound: enough headroom above the current value for normal
  /// receipt quantities, with a floor so tiny starting values still feel
  /// scrollable (e.g. qty=1 still reaches at least 30).
  late final int _upperBound =
      widget.initialQuantity + 20 < 30 ? 30 : widget.initialQuantity + 20;
  late int _selected;
  late final FixedExtentScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initialQuantity.clamp(1, _upperBound);
    _selected = clamped;
    _scrollController = FixedExtentScrollController(initialItem: clamped - 1);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ReceiptSheetHandle(),
            const SizedBox(height: 18),
            Text(
              widget.itemName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: balooText(
                20,
                FontWeight.w800,
                color: ReceiptSheetColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quantity',
              textAlign: TextAlign.center,
              style: balooText(
                14,
                FontWeight.w600,
                color: ReceiptSheetColors.subLight,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: CupertinoPicker(
                key: const Key('receipt-quantity-picker'),
                scrollController: _scrollController,
                itemExtent: 48,
                selectionOverlay: CupertinoPickerDefaultSelectionOverlay(
                  // selectedTint is fully opaque — dial it down so the
                  // centered number stays readable through the highlight.
                  background: ReceiptSheetColors.selectedTint.withValues(
                    alpha: 0.35,
                  ),
                ),
                onSelectedItemChanged: (i) {
                  setState(() => _selected = i + 1);
                },
                children: [
                  for (var q = 1; q <= _upperBound; q++)
                    Center(
                      child: Text(
                        '$q',
                        style: balooText(
                          34,
                          FontWeight.w800,
                          color: ReceiptSheetColors.ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ReceiptSheetCta(
              label: 'Done',
              onPressed: () => Navigator.pop(context, _selected),
            ),
          ],
        ),
      ),
    );
  }
}
