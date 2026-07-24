import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/models/field_correction.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import '../places/place_picker_screen.dart';
import '../places/places_search_screen.dart';
import 'receipt_ingest_draft.dart';
import 'receipt_summary_view_model.dart';

/// Post-OCR receipt confirmation + save sheet (design handoff Screen 1,
/// `docs/design/design_handoff_receipt_flows/`, extended to absorb what used
/// to be a separate `ShareSaveSheet` step — see `docs/decisions.md`).
///
/// Lets the user review vendor / category / total / itemized breakdown /
/// impact before saving: tapping an item's checkbox excludes it (the total
/// recalculates and an Undo banner appears), tapping an item's price lets
/// the user correct it (the total recalculates), tapping the vendor name
/// renames it inline, tapping the pencil opens the nearby-location picker to
/// lock the vendor's place, and this is also where the receipt is actually
/// persisted (Save / Save for later / Cancel).
///
/// [show] returns `true` only when the user completed a save; `false` for
/// cancel or "save for later" (parked in the review queue, not a celebrated
/// save).
class ReceiptConfirmSheet extends StatefulWidget {
  const ReceiptConfirmSheet({
    super.key,
    required this.draft,
    required this.categories,
    required this.onSave,
    required this.onCancel,
    this.onSaveForLater,
  });

  final ReceiptIngestDraft draft;

  /// Category rules used to populate the inline category picker.
  final CategoryConfig categories;

  final Future<void> Function(
    double? amount,
    ReceiptIngestDraft draft,
    ImpactLevel impact,
  ) onSave;
  final Future<void> Function(ReceiptIngestDraft draft) onCancel;

  /// Parks the receipt in the review queue instead of confirming now.
  /// Offered only for needs-amount / low-confidence drafts.
  final Future<void> Function(ReceiptIngestDraft draft)? onSaveForLater;

  static Future<bool> show(
    BuildContext context, {
    required ReceiptIngestDraft draft,
    required CategoryConfig categories,
    required Future<void> Function(
      double? amount,
      ReceiptIngestDraft draft,
      ImpactLevel impact,
    ) onSave,
    required Future<void> Function(ReceiptIngestDraft draft) onCancel,
    Future<void> Function(ReceiptIngestDraft draft)? onSaveForLater,
  }) async {
    final result = await AdaptiveSheet.showForm<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ReceiptSheetColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: ReceiptConfirmSheet(
        draft: draft,
        categories: categories,
        onSave: onSave,
        onCancel: onCancel,
        onSaveForLater: onSaveForLater,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReceiptConfirmSheet> createState() => _ReceiptConfirmSheetState();
}

/// Cap on the internal items scroll box (~5.5 rows), so vendor / category /
/// amount / impact and the pinned Save button stay on screen no matter how
/// many line items a receipt has.
const _itemsMaxHeight = 215.0;

/// Estimated per-row height (row ~24px + 14px separator) used to decide
/// whether the items list can overflow [_itemsMaxHeight] and therefore
/// whether the scrollbar thumb should be shown at all.
const _itemRowExtentEstimate = 38.0;

class _ReceiptConfirmSheetState extends State<ReceiptConfirmSheet> {
  late final List<ReceiptLineItem> _items;
  final ScrollController _itemsScrollController = ScrollController();
  late final List<bool> _checked;
  late List<double> _prices;
  late String _vendorName;
  late bool _vendorKnown;
  bool _vendorEdited = false;
  bool _editingVendor = false;
  int? _undoIndex;
  Timer? _undoTimer;
  late final TextEditingController _vendorController;
  final FocusNode _vendorFocus = FocusNode();
  int? _editingPriceIndex;
  late final TextEditingController _priceController;
  final FocusNode _priceFocus = FocusNode();
  PlaceResult? _pickedPlace;
  late final bool _needsManualAmount;
  late final bool _lowConfidence;
  late final bool _amountFieldLow;
  late final bool _merchantFieldLow;
  late final bool _amountSuspicious;
  late final bool _merchantAmbiguous;
  late final double? _amountAlternative;
  late final TextEditingController _amountController;
  String? _categoryOverride;
  ImpactLevel? _impactOverride;
  bool _saving = false;
  bool _showAmountAlternative = true;
  bool _showMerchantAlternative = true;
  double? _amountOverride;

  @override
  void initState() {
    super.initState();
    final vm = ReceiptSummaryViewModel.from(widget.draft);
    _items = widget.draft.lineItems;
    _checked = List.filled(_items.length, true);
    _prices = [for (final item in _items) item.priceMyr];
    _vendorName = vm.merchantDisplay;
    _vendorKnown = widget.draft.merchantRaw?.trim().isNotEmpty ?? false;
    _needsManualAmount = widget.draft.needsAmount;
    _lowConfidence = vm.isLowConfidence;
    _amountSuspicious = widget.draft.amountSuspicious;
    _amountFieldLow =
        widget.draft.amountFieldLowConfidence || _amountSuspicious;
    _merchantAmbiguous = widget.draft.merchantAmbiguous;
    _merchantFieldLow = _merchantAmbiguous ||
        (widget.draft.merchantConfidence != null &&
            widget.draft.merchantConfidence! < 0.5);
    _amountAlternative = widget.draft.amountAlternativeMyr;
    _vendorController = TextEditingController();
    _vendorFocus.addListener(() {
      if (!_vendorFocus.hasFocus && _editingVendor) _commitVendor();
    });
    _priceController = TextEditingController();
    _priceFocus.addListener(() {
      if (!_priceFocus.hasFocus && _editingPriceIndex != null) {
        _commitPriceEdit();
      }
    });
    _amountController = TextEditingController();
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _itemsScrollController.dispose();
    _vendorController.dispose();
    _vendorFocus.dispose();
    _priceController.dispose();
    _priceFocus.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// The parsed receipt total adjusted for excluded items and any per-item
  /// price corrections. Starting from the OCR total (instead of re-summing
  /// checked items) keeps tax and service charge intact when the printed
  /// items don't add up to the total; an edited item's delta from its
  /// original OCR price is folded in on top of that baseline.
  double? get _total {
    final base = _amountOverride ??
        widget.draft.amountMyr ??
        (_items.isEmpty
            ? null
            : _items.fold<double>(0, (sum, item) => sum + item.priceMyr));
    if (base == null) return null;
    var total = base;
    for (var i = 0; i < _items.length; i++) {
      if (_checked[i]) {
        total += _prices[i] - _items[i].priceMyr;
      } else {
        total -= _items[i].priceMyr;
      }
    }
    return total < 0 ? 0 : total;
  }

  void _acceptAmountAlternative() {
    final alt = _amountAlternative;
    if (alt == null) return;
    setState(() {
      _amountOverride = alt;
      _showAmountAlternative = false;
    });
  }

  /// The amount actually used to save: the manual field for drafts OCR
  /// couldn't find a total on, otherwise the item-adjusted OCR total above.
  double? get _effectiveAmount {
    if (_needsManualAmount) {
      final raw = _amountController.text.trim().replaceAll(',', '');
      return raw.isEmpty ? null : double.tryParse(raw);
    }
    return _total;
  }

  ImpactLevel get _effectiveImpact =>
      _impactOverride ?? deriveImpactLevel(_effectiveAmount);

  bool get _canSaveForLater =>
      widget.onSaveForLater != null &&
      (widget.draft.needsAmount || _lowConfidence || _amountSuspicious);

  int get _includedCount => _checked.where((c) => c).length;

  bool get _anyExcluded => _checked.contains(false);

  bool get _anyPriceEdited {
    for (var i = 0; i < _items.length; i++) {
      if (_prices[i] != _items[i].priceMyr) return true;
    }
    return false;
  }

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

  void _startPriceEdit(int index) {
    if (_editingPriceIndex != null && _editingPriceIndex != index) {
      _commitPriceEdit();
    }
    setState(() {
      _editingPriceIndex = index;
      _priceController.text = _prices[index].toStringAsFixed(2);
      _priceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _priceController.text.length,
      );
    });
  }

  void _commitPriceEdit() {
    final index = _editingPriceIndex;
    if (index == null) return;
    final parsed =
        double.tryParse(_priceController.text.trim().replaceAll(',', ''));
    setState(() {
      if (parsed != null && parsed >= 0) _prices[index] = parsed;
      _editingPriceIndex = null;
    });
  }

  /// Opens the nearby-place picker (top ranked candidates within the
  /// enrichment search radius) so the user can lock the vendor's location,
  /// mirroring `ShareSaveSheet._openPicker` (now merged into this sheet).
  Future<void> _openPlacePicker() async {
    final lat = widget.draft.shareLocationLat;
    final lng = widget.draft.shareLocationLng;
    // No share-time GPS fix (permission denied, location off, or no fix
    // within the timeout) — fall back to text search instead of just
    // hiding the button, mirroring transaction_detail_screen.dart's
    // _pickPlace(). Pushed via the root navigator, same as
    // PlacePickerScreen.push, since this sheet runs inside a modal sheet
    // where go_router's context.pushNamed doesn't reliably navigate.
    final result = lat != null && lng != null
        ? await PlacePickerScreen.push(
            context,
            lat: lat,
            lng: lng,
            candidates: widget.draft.merchantCandidates,
            merchantName: _vendorName,
            category: _categoryOverride ?? widget.draft.categoryGuess,
          )
        : await Navigator.of(context, rootNavigator: true)
            .push<PlaceResult?>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const PlacesSearchScreen(),
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      _pickedPlace = result;
      _vendorName = result.name;
      _vendorEdited = true;
    });
  }

  /// The draft with the user's edits applied, passed to [widget.onSave] /
  /// [widget.onSaveForLater] — the confirmed amount is passed separately to
  /// [widget.onSave], not folded into this draft's `amountMyr`.
  ReceiptIngestDraft _editedDraft() {
    final anyItemChange = _anyExcluded || _anyPriceEdited;
    return widget.draft.copyWith(
      merchantRaw: _vendorEdited ? _vendorName : null,
      categoryUser: _categoryOverride,
      lineItems: anyItemChange
          ? [
              for (var i = 0; i < _items.length; i++)
                if (_checked[i]) _items[i].copyWith(priceMyr: _prices[i]),
            ]
          : null,
      pickedPlaceName: _pickedPlace?.name,
      pickedPlaceGooglePlaceId: _pickedPlace?.id,
      pickedPlaceLat: _pickedPlace?.lat,
      pickedPlaceLng: _pickedPlace?.lng,
      pickedPlaceLocked: _pickedPlace != null,
      fieldCorrections: _buildFieldCorrections(),
    );
  }

  /// Captures a predicted-vs-confirmed diff for every field the user
  /// actually changed, at the one point both values are still simultaneously
  /// in scope — immediately before the call above folds the confirmed
  /// values into the saved draft, after which the originals are
  /// unrecoverable (see `docs/plans/2026-07-23-feedback-learning-system.md`,
  /// Problem Statement #1). Fields left unchanged emit nothing, so storage
  /// isn't flooded with "no correction" noise.
  List<FieldCorrection> _buildFieldCorrections() {
    final corrections = <FieldCorrection>[];
    final predictedMerchant = widget.draft.merchantRaw;

    if (_vendorEdited &&
        predictedMerchant != null &&
        predictedMerchant != _vendorName) {
      corrections.add(FieldCorrection(
        field: FieldCorrection.fieldMerchant,
        predictedValue: predictedMerchant,
        confirmedValue: _vendorName,
        merchantRaw: predictedMerchant,
        confidence: widget.draft.merchantConfidence,
        // A picker pick is a deliberate, multi-step action — a much
        // stronger signal than a quick free-text rename (Decision Logic).
        correctionType: _pickedPlace != null
            ? FieldCorrection.correctionTypeUserLocked
            : FieldCorrection.correctionTypeFreeText,
      ));
    }

    if (_categoryOverride != null &&
        _categoryOverride != widget.draft.categoryGuess) {
      corrections.add(FieldCorrection(
        field: FieldCorrection.fieldCategory,
        predictedValue: widget.draft.categoryGuess,
        confirmedValue: _categoryOverride!,
        merchantRaw: predictedMerchant,
        confidence: widget.draft.categoryConfidence,
      ));
    }

    final predictedAmount = widget.draft.amountMyr;
    if (_amountOverride != null &&
        predictedAmount != null &&
        _amountOverride != predictedAmount) {
      corrections.add(FieldCorrection(
        field: FieldCorrection.fieldAmount,
        predictedValue: FieldCorrection.formatAmount(predictedAmount),
        confirmedValue: FieldCorrection.formatAmount(_amountOverride!),
        merchantRaw: predictedMerchant,
        confidence: widget.draft.ocrConfidence,
      ));
    }

    for (var i = 0; i < _items.length; i++) {
      if (_prices[i] != _items[i].priceMyr) {
        corrections.add(FieldCorrection(
          field: FieldCorrection.fieldLineItemPrice,
          predictedValue: FieldCorrection.formatAmount(_items[i].priceMyr),
          confirmedValue: FieldCorrection.formatAmount(_prices[i]),
          merchantRaw: predictedMerchant,
          confidence: _items[i].confidence,
          lineItemIndex: i,
        ));
      }
    }

    return corrections;
  }

  Future<void> _save() async {
    if (_editingVendor) _commitVendor();
    if (_editingPriceIndex != null) _commitPriceEdit();
    final amount = _effectiveAmount;
    if (amount == null || amount <= 0) {
      PlatformFeedback.showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(amount, _editedDraft(), _effectiveImpact);
      if (mounted) {
        PlatformFeedback.mediumTap();
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveForLater() async {
    setState(() => _saving = true);
    try {
      await widget.onSaveForLater!(_editedDraft());
      if (mounted) {
        PlatformFeedback.mediumTap();
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    await widget.onCancel(widget.draft);
    if (mounted) Navigator.pop(context, false);
  }

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
              category: _categoryOverride ?? widget.draft.categoryGuess,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldConfidenceWrap(
                    lowConfidence: _merchantFieldLow,
                    child: _editingVendor ? _vendorField() : _vendorLabel(),
                  ),
                  if (_merchantAmbiguous &&
                      _showMerchantAlternative &&
                      widget.draft.merchantCandidates.length >= 2) ...[
                    const SizedBox(height: 6),
                    _AlternativeChip(
                      label:
                          'Not this? ${widget.draft.merchantCandidates[1].text}',
                      onTap: () {
                        setState(() {
                          _vendorName =
                              widget.draft.merchantCandidates[1].text;
                          _vendorEdited = true;
                          _showMerchantAlternative = false;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: ReceiptSheetColors.tile,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openPlacePicker,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(
                    Icons.edit_location_outlined,
                    size: 15,
                    color: ReceiptSheetColors.sub,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text('Category', style: balooText(13, FontWeight.w700, color: ReceiptSheetColors.subLight)),
        const SizedBox(height: 6),
        _CategoryDropdown(
          value: _categoryOverride ?? widget.draft.categoryGuess,
          categories: widget.categories,
          onChanged: (v) => setState(() => _categoryOverride = v),
        ),
        const SizedBox(height: 14),
        _needsManualAmount
            ? AmountField(controller: _amountController)
            : _FieldConfidenceWrap(
                lowConfidence: _amountFieldLow,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    if (_amountAlternative != null &&
                        _showAmountAlternative &&
                        total != null &&
                        (_amountAlternative - total).abs() >= 0.01) ...[
                      const SizedBox(height: 6),
                      _AlternativeChip(
                        label:
                            'Did you mean RM ${_amountAlternative.toStringAsFixed(2)}?',
                        onTap: () {
                          setState(() {
                            _showAmountAlternative = false;
                          });
                          _acceptAmountAlternative();
                        },
                      ),
                    ],
                  ],
                ),
              ),
        const SizedBox(height: 14),
        Text('Impact', style: balooText(13, FontWeight.w700, color: ReceiptSheetColors.subLight)),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final level in ImpactLevel.values) ...[
              if (level != ImpactLevel.values.first) const SizedBox(width: 8),
              Expanded(
                child: _ImpactChip(
                  level: level,
                  selected: _effectiveImpact == level,
                  onTap: () => setState(() => _impactOverride = level),
                ),
              ),
            ],
          ],
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _itemsMaxHeight),
            child: RawScrollbar(
              controller: _itemsScrollController,
              thumbVisibility:
                  _items.length * _itemRowExtentEstimate - 14 >
                      _itemsMaxHeight,
              thickness: 3,
              radius: const Radius.circular(3),
              thumbColor: ReceiptSheetColors.subLight,
              child: ListView.separated(
                controller: _itemsScrollController,
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                // Right gutter keeps the scrollbar clear of the prices;
                // bottom padding keeps the last row from sitting flush
                // against the box edge once fully scrolled into view.
                padding: const EdgeInsets.fromLTRB(0, 0, 12, 12),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) => _ItemRow(
                  item: _items[i],
                  price: _prices[i],
                  checked: _checked[i],
                  editing: _editingPriceIndex == i,
                  lowConfidence: (_items[i].confidence ?? 1.0) < 0.5,
                  priceController: _priceController,
                  priceFocus: _priceFocus,
                  onToggle: () => _toggleItem(i),
                  onEditPrice: () => _startPriceEdit(i),
                ),
              ),
            ),
          ),
        ],
        if (_lowConfidence || _amountSuspicious) ...[
          const SizedBox(height: 14),
          _NoticeBanner(
            text: widget.draft.needsAmount
                ? "We couldn't read the amount — enter it above."
                : _amountSuspicious
                    ? "This total looks uncertain — check the highlighted fields or save for later."
                    : _amountFieldLow || _merchantFieldLow
                        ? "Double-check the highlighted fields — we're not fully sure."
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
          label: 'Save',
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: 8),
        if (_canSaveForLater)
          ReceiptSheetLink(
            label: 'Save for later',
            color: ReceiptSheetColors.link,
            onTap: _saving ? null : _saveForLater,
          ),
        ReceiptSheetLink(
          label: 'Cancel',
          color: ReceiptSheetColors.subLight,
          onTap: _saving ? null : _cancel,
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
    return GestureDetector(
      onTap: _startVendorEdit,
      behavior: HitTestBehavior.opaque,
      child: Text(
        _vendorName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: balooText(
          20,
          FontWeight.w800,
          color: ReceiptSheetColors.ink,
          letterSpacing: -0.2,
        ),
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

/// Category dropdown, ported from the now-removed `ShareSaveSheet`. Deliberately
/// Material-styled (not `balooText`/`ReceiptSheetColors`), same as [AmountField]
/// below — both are reused as-is rather than re-skinned for this sheet.
class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.value,
    required this.categories,
    required this.onChanged,
  });

  final String value;
  final CategoryConfig categories;
  final ValueChanged<String?> onChanged;

  List<String> get _items => {
        ...categories.rules.map((r) => r.category),
        categories.defaultCategory,
      }.toList();

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final safeValue = items.contains(value) ? value : items.first;
    return DropdownButtonFormField<String>(
      initialValue: safeValue,
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        isDense: true,
      ),
      items: items.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
      onChanged: onChanged,
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
      case 'Travel':
        return '✈️';
      case 'Health & Beauty':
        return '💊';
      default:
        return '🧾';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ties this bubble's color into the same per-category coding used
    // app-wide (CategoryChip, transaction_list_tile.dart/summary_screen.dart)
    // instead of a flat sheet-local color, so a receipt's category reads
    // consistently wherever it's shown.
    final color = AppColors.categoryColor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 7),
          Text(
            category,
            style: balooText(13, FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

/// Impact chip, ported unchanged from the now-removed `ShareSaveSheet` —
/// same visual format the request asked for, reused verbatim.
class _ImpactChip extends StatelessWidget {
  const _ImpactChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final ImpactLevel level;
  final bool selected;
  final VoidCallback onTap;

  Color get _color {
    switch (level) {
      case ImpactLevel.low:
        return AppColors.impactLow;
      case ImpactLevel.med:
        return AppColors.impactMed;
      case ImpactLevel.high:
        return AppColors.impactHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.chipBorderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _color : AppColors.cardSurface,
          borderRadius: AppSpacing.chipBorderRadius,
          border: Border.all(
            color: selected ? _color : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          level.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.price,
    required this.checked,
    required this.editing,
    required this.priceController,
    required this.priceFocus,
    required this.onToggle,
    required this.onEditPrice,
    this.lowConfidence = false,
  });

  final ReceiptLineItem item;
  final double price;
  final bool checked;
  final bool editing;
  final bool lowConfidence;
  final TextEditingController priceController;
  final FocusNode priceFocus;
  final VoidCallback onToggle;
  final VoidCallback onEditPrice;

  @override
  Widget build(BuildContext context) {
    return _FieldConfidenceWrap(
      lowConfidence: lowConfidence,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: onToggle,
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
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: checked ? 1 : 0.4,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: balooText(
                          15,
                          FontWeight.w700,
                          decoration:
                              checked ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Opacity(
            opacity: checked ? 1 : 0.4,
            child: Text(
              '×${item.quantity ?? 1}',
              style: balooText(
                13,
                FontWeight.w600,
                color: ReceiptSheetColors.subLight,
              ),
            ),
          ),
          const SizedBox(width: 10),
          editing ? _priceField() : _priceLabel(),
        ],
      ),
    );
  }

  Widget _priceLabel() {
    return GestureDetector(
      onTap: onEditPrice,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: checked ? 1 : 0.4,
        child: Text(
          'RM ${price.toStringAsFixed(2)}',
          style: balooText(15, FontWeight.w700),
        ),
      ),
    );
  }

  Widget _priceField() {
    const goldUnderline = UnderlineInputBorder(
      borderSide: BorderSide(color: ReceiptSheetColors.gold, width: 2),
    );
    return SizedBox(
      width: 78,
      child: TextField(
        controller: priceController,
        focusNode: priceFocus,
        autofocus: true,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => priceFocus.unfocus(),
        cursorColor: ReceiptSheetColors.gold,
        style: balooText(15, FontWeight.w700),
        decoration: const InputDecoration(
          isDense: true,
          filled: false,
          prefixText: 'RM ',
          contentPadding: EdgeInsets.only(bottom: 2),
          border: goldUnderline,
          enabledBorder: goldUnderline,
          focusedBorder: goldUnderline,
        ),
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

/// Subtle warning-tinted border around a low-confidence field.
class _FieldConfidenceWrap extends StatelessWidget {
  const _FieldConfidenceWrap({
    required this.lowConfidence,
    required this.child,
  });

  final bool lowConfidence;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!lowConfidence) return child;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.impactMed.withValues(alpha: 0.7),
          width: 1.5,
        ),
        color: AppColors.impactMed.withValues(alpha: 0.06),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: AppColors.impactMed.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Compact "did you mean / not this?" affordance for ambiguous candidates.
class _AlternativeChip extends StatelessWidget {
  const _AlternativeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: balooText(
          13,
          FontWeight.w700,
          color: ReceiptSheetColors.linkStrong,
        ),
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
