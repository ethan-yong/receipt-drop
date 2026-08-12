import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/platform/platform_feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/models/field_correction.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../widgets/quantity_picker_sheet.dart';
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
/// persisted (Save / Cancel).
///
/// [show] returns `true` only when the user completed a save; `false` for
/// cancel.
class ReceiptConfirmSheet extends StatefulWidget {
  const ReceiptConfirmSheet({
    super.key,
    required this.draft,
    required this.categories,
    required this.onSave,
    required this.onCancel,
    @visibleForTesting this.mapOverride,
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

  /// Overrides the real `GoogleMap` thumbnail in the location-preview tile
  /// in widget tests, which can't construct a live platform view outside a
  /// real device/emulator. Mirrors `PlacePickerScreen.mapOverride`.
  @visibleForTesting
  final Widget? mapOverride;

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
    @visibleForTesting Widget? mapOverride,
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
        mapOverride: mapOverride,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReceiptConfirmSheet> createState() => _ReceiptConfirmSheetState();
}

/// Cap on the internal items scroll box (~5 rows), so vendor / category /
/// amount / impact and the pinned Save button stay on screen no matter how
/// many line items a receipt has.
const _itemsMaxHeight = 240.0;

/// Estimated per-row height (~28px row + 2px separator) used
/// to decide whether the items list can overflow [_itemsMaxHeight] and
/// therefore whether the scrollbar thumb should be shown at all.
const _itemRowExtentEstimate = 30.0;

/// Soft cap for the banking-style cents buffer (RM 9,999,999.99).
const _maxAmountCents = 999999999;

int _myrToCents(double myr) =>
    (myr * 100).round().clamp(0, _maxAmountCents);

String _formatAmountCents(int cents) {
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '$whole.$frac';
}

class _ReceiptConfirmSheetState extends State<ReceiptConfirmSheet> {
  late final List<ReceiptLineItem> _items;
  final ScrollController _itemsScrollController = ScrollController();
  final ScrollController _bodyScrollController = ScrollController();
  final GlobalKey _nameFieldKey = GlobalKey();
  final GlobalKey _priceFieldKey = GlobalKey();
  final GlobalKey _bodyKey = GlobalKey();
  final GlobalKey _actionsKey = GlobalKey();
  late final List<bool> _checked;
  late List<double> _prices;
  late List<String> _names;
  late List<int> _quantities;
  late String _vendorName;
  late bool _vendorKnown;
  bool _vendorEdited = false;
  bool _editingVendor = false;
  int? _undoIndex;
  Timer? _undoTimer;
  Timer? _ensureVisibleTimer;
  late final TextEditingController _vendorController;
  final FocusNode _vendorFocus = FocusNode();
  int? _editingPriceIndex;
  late final TextEditingController _priceController;
  final FocusNode _priceFocus = FocusNode();
  int? _editingNameIndex;
  late final TextEditingController _nameController;
  final FocusNode _nameFocus = FocusNode();
  PlaceResult? _pickedPlace;
  PlaceResult? _previewPlace;
  bool _previewLoading = true;
  late final bool _amountFieldLow;
  late final bool _merchantFieldLow;
  late final bool _amountSuspicious;
  late final bool _merchantAmbiguous;
  late final double? _amountAlternative;
  /// Banking-style amount buffer in cents (always displays as RM X.YY).
  int _amountCents = 0;
  bool _amountKeypadOpen = false;
  String? _categoryOverride;
  ImpactLevel? _impactOverride;
  bool _saving = false;
  bool _showAmountAlternative = true;
  bool _amountManuallyEdited = false;
  double? _amountOverride;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final vm = ReceiptSummaryViewModel.from(widget.draft);
    _notesController = TextEditingController(text: widget.draft.notes ?? '');
    _items = widget.draft.lineItems;
    _checked = List.filled(_items.length, true);
    _prices = [for (final item in _items) item.priceMyr];
    _names = [for (final item in _items) item.name];
    _quantities = [for (final item in _items) item.quantity ?? 1];
    _vendorName = vm.merchantDisplay;
    _vendorKnown = widget.draft.merchantRaw?.trim().isNotEmpty ?? false;
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
    _nameController = TextEditingController();
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingNameIndex != null) {
        _commitNameEdit();
      }
    });
    _amountCents = _total != null ? _myrToCents(_total!) : 0;
    unawaited(_resolvePreviewLocation());
  }

  /// Keeps the (editable) total following item checkboxes/price edits, unless
  /// the user has entered an amount on the keypad — once they have, an item
  /// toggle must not silently overwrite what they typed.
  void _syncAmountFromItems() {
    if (_amountManuallyEdited) return;
    final total = _total;
    _amountCents = total != null ? _myrToCents(total) : 0;
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _ensureVisibleTimer?.cancel();
    _itemsScrollController.dispose();
    _bodyScrollController.dispose();
    _vendorController.dispose();
    _vendorFocus.dispose();
    _priceController.dispose();
    _priceFocus.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _notesController.dispose();
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
      _syncAmountFromItems();
    });
  }

  /// The amount actually used to save — always whatever the cents buffer
  /// currently shows, whether that came from OCR, an item-sum fallback, or
  /// the user entering digits on the keypad.
  double get _effectiveAmount => _amountCents / 100.0;

  String get _amountDisplayLabel => 'RM ${_formatAmountCents(_amountCents)}';

  void _toggleAmountKeypad() {
    _commitAllPendingEdits();
    setState(() => _amountKeypadOpen = !_amountKeypadOpen);
  }

  void _appendAmountDigit(int digit) {
    setState(() {
      _amountManuallyEdited = true;
      _showAmountAlternative = false;
      final next = _amountCents * 10 + digit;
      if (next <= _maxAmountCents) _amountCents = next;
    });
  }

  void _backspaceAmountDigit() {
    setState(() {
      _amountManuallyEdited = true;
      _showAmountAlternative = false;
      _amountCents = _amountCents ~/ 10;
    });
  }

  void _confirmAmountKeypad() {
    setState(() {
      _amountManuallyEdited = true;
      _amountOverride = _effectiveAmount;
      _amountKeypadOpen = false;
      _showAmountAlternative = false;
    });
  }

  ImpactLevel get _effectiveImpact =>
      _impactOverride ?? deriveImpactLevel(_effectiveAmount);

  int get _includedCount => _checked.where((c) => c).length;

  bool get _anyExcluded => _checked.contains(false);

  bool get _anyPriceEdited {
    for (var i = 0; i < _items.length; i++) {
      if (_prices[i] != _items[i].priceMyr) return true;
    }
    return false;
  }

  bool get _anyNameEdited {
    for (var i = 0; i < _items.length; i++) {
      if (_names[i] != _items[i].name) return true;
    }
    return false;
  }

  bool get _anyQuantityEdited {
    for (var i = 0; i < _items.length; i++) {
      if (_quantities[i] != (_items[i].quantity ?? 1)) return true;
    }
    return false;
  }

  void _toggleItem(int index) {
    _commitAllPendingEdits();
    _undoTimer?.cancel();
    final nowChecked = !_checked[index];
    setState(() {
      _checked[index] = nowChecked;
      if (!nowChecked) {
        _undoIndex = index;
      } else if (_undoIndex == index) {
        _undoIndex = null;
      }
      _syncAmountFromItems();
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
      _syncAmountFromItems();
    });
  }

  void _commitAllPendingEdits() {
    if (_editingVendor) _commitVendor();
    if (_editingPriceIndex != null) _commitPriceEdit();
    if (_editingNameIndex != null) _commitNameEdit();
  }

  void _startVendorEdit() {
    _commitAllPendingEdits();
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
    _commitAllPendingEdits();
    setState(() {
      _editingPriceIndex = index;
      _priceController.text = _prices[index].toStringAsFixed(2);
      _priceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _priceController.text.length,
      );
    });
    _scrollItemIntoView(index);
    _ensureFieldVisible(_priceFieldKey);
  }

  void _commitPriceEdit() {
    final index = _editingPriceIndex;
    if (index == null) return;
    final parsed =
        double.tryParse(_priceController.text.trim().replaceAll(',', ''));
    setState(() {
      if (parsed != null && parsed >= 0) _prices[index] = parsed;
      _editingPriceIndex = null;
      _syncAmountFromItems();
    });
  }

  void _startNameEdit(int index) {
    _commitAllPendingEdits();
    setState(() {
      _editingNameIndex = index;
      _nameController.text = _names[index];
    });
    _scrollItemIntoView(index);
    _ensureFieldVisible(_nameFieldKey);
    // Autofocus can collapse selection after mount — re-select the whole
    // name so the next keystroke replaces it immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingNameIndex != index) return;
      _nameFocus.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  /// Scrolls the internal items list so [index] is near the top of that box.
  /// Name edits stay single-row (inline), so the default row estimate is enough
  /// for the initial scroll; [_ensureFieldVisible] then parks the field above
  /// the keyboard.
  void _scrollItemIntoView(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemsScrollController.hasClients) return;
      final target = (index * _itemRowExtentEstimate).clamp(
        0.0,
        _itemsScrollController.position.maxScrollExtent,
      );
      _itemsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Scrolls ancestor scrollables so [fieldKey] sits above the keyboard.
  /// Runs once after the next frame and again after the keyboard animation
  /// settles, because viewInsets usually arrive a beat after autofocus.
  void _ensureFieldVisible(GlobalKey fieldKey) {
    void reveal() {
      final ctx = fieldKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        // Keep the field in the upper third of the visible scroll area so
        // the keyboard sits cleanly below it rather than covering it.
        alignment: 0.15,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      reveal();
      _ensureVisibleTimer?.cancel();
      _ensureVisibleTimer = Timer(const Duration(milliseconds: 350), reveal);
    });
  }

  void _commitNameEdit() {
    final index = _editingNameIndex;
    if (index == null) return;
    final text = _nameController.text.trim();
    setState(() {
      if (text.isNotEmpty) _names[index] = text;
      _editingNameIndex = null;
    });
  }

  Future<void> _startQuantityEdit(int index) async {
    _commitAllPendingEdits();
    final result = await AdaptiveSheet.showForm<int>(
      context: context,
      backgroundColor: ReceiptSheetColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: QuantityPickerSheet(
        itemName: _names[index],
        initialQuantity: _quantities[index],
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _quantities[index] = result);
  }

  /// Undo banner label using the (possibly edited) name + quantity.
  String _itemDisplayLabel(int index) {
    final name = _names[index];
    final qty = _quantities[index];
    return qty > 1 ? '$qty× $name' : name;
  }

  /// Best-effort receipt-derived location query, checked in the order the
  /// LLM understanding step's fields most reliably encode an actual place: a
  /// ready-made Places search query is best, then a raw address, then a
  /// looser location clue — each combined with the current vendor name for
  /// precision. Returns null when there's no textual signal at all, so
  /// [_resolvePreviewLocation] falls back to the device's GPS fix instead.
  String? _receiptLocationQuery() {
    final u = widget.draft.understanding;
    if (u == null) return null;

    final query = u.merchantSearchQueries.firstWhere(
      (q) => q.trim().isNotEmpty,
      orElse: () => '',
    );
    if (query.isNotEmpty) return query.trim();

    final vendor = _vendorName.trim();
    final address = u.addressText?.trim();
    if (address != null && address.isNotEmpty) {
      return vendor.isEmpty ? address : '$vendor, $address';
    }

    final clue = u.locationClues.firstWhere(
      (c) => c.trim().isNotEmpty,
      orElse: () => '',
    );
    if (clue.isNotEmpty) return vendor.isEmpty ? clue : '$vendor $clue';

    return null;
  }

  /// Auto-resolves a best-guess center for the tappable map preview — never
  /// sets [_pickedPlace] (that's reserved for an explicit user pick via
  /// [_openPlacePicker] and drives `pickedPlaceLocked` on save). Priority:
  /// receipt-derived text (unbiased, so it isn't pulled toward the device's
  /// GPS fix) > GPS-nearby candidates (today's existing ranked search,
  /// still merchant/candidate-aware) > a last-resort unbiased name-only
  /// search > nothing (empty state).
  Future<void> _resolvePreviewLocation() async {
    PlaceResult? result;
    try {
      final query = _receiptLocationQuery();
      if (query != null) {
        final results = await PlacesRepository.search(query);
        if (results.isNotEmpty) result = results.first;
      }

      if (result == null) {
        final lat = widget.draft.shareLocationLat;
        final lng = widget.draft.shareLocationLng;
        if (lat != null && lng != null) {
          final candidates = await PlacesRepository.fetchNearbyCandidates(
            lat: lat,
            lng: lng,
            candidates: widget.draft.merchantCandidates,
            merchantName: _vendorName,
            category: _categoryOverride ?? widget.draft.categoryGuess,
          );
          if (candidates.isNotEmpty) result = candidates.first.toPlaceResult();
        }
      }

      if (result == null) {
        final fallbackQuery = _vendorName.trim().isNotEmpty
            ? _vendorName.trim()
            : widget.draft.merchantCandidates.isNotEmpty
                ? widget.draft.merchantCandidates.first.text
                : null;
        if (fallbackQuery != null) {
          final results = await PlacesRepository.search(fallbackQuery);
          if (results.isNotEmpty) result = results.first;
        }
      }
    } on Object {
      result = null;
    }
    if (!mounted) return;
    setState(() {
      _previewPlace = result;
      _previewLoading = false;
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

  /// The draft with the user's edits applied, passed to [widget.onSave] —
  /// the confirmed amount is passed separately to [widget.onSave], not
  /// folded into this draft's `amountMyr`.
  ReceiptIngestDraft _editedDraft() {
    final anyItemChange =
        _anyExcluded || _anyPriceEdited || _anyNameEdited || _anyQuantityEdited;
    final place = _pickedPlace ?? _previewPlace;
    return widget.draft.copyWith(
      merchantRaw: _vendorEdited ? _vendorName : null,
      categoryUser: _categoryOverride,
      lineItems: anyItemChange
          ? [
              for (var i = 0; i < _items.length; i++)
                if (_checked[i])
                  _items[i].copyWith(
                    name: _names[i],
                    priceMyr: _prices[i],
                    // Only override when the user actually changed quantity —
                    // otherwise preserve OCR-undetected null rather than
                    // silently promoting it to 1 during an unrelated edit.
                    quantity: _quantities[i] != (_items[i].quantity ?? 1)
                        ? _quantities[i]
                        : null,
                  ),
            ]
          : null,
      pickedPlaceName: place?.name,
      pickedPlaceGooglePlaceId: place?.id,
      pickedPlaceLat: place?.lat,
      pickedPlaceLng: place?.lng,
      pickedPlaceLocked: _pickedPlace != null,
      fieldCorrections: _buildFieldCorrections(),
      // Same "no explicit clear" convention as the vendor-name field above:
      // an edit sets a new note, but backspacing to empty doesn't erase an
      // already-attached one (e.g. from the post-share notification reply).
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    );
  }

  /// Waits for the receipt-derived preview place if the user saves before
  /// [_resolvePreviewLocation] finishes.
  Future<void> _ensurePreviewResolved() async {
    if (_previewLoading) {
      await _resolvePreviewLocation();
    }
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
    final confirmedAmount = _amountManuallyEdited
        ? _effectiveAmount
        : _amountOverride;
    if (confirmedAmount != null &&
        predictedAmount != null &&
        (confirmedAmount - predictedAmount).abs() >= 0.005) {
      corrections.add(FieldCorrection(
        field: FieldCorrection.fieldAmount,
        predictedValue: FieldCorrection.formatAmount(predictedAmount),
        confirmedValue: FieldCorrection.formatAmount(confirmedAmount),
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
    _commitAllPendingEdits();
    if (_amountKeypadOpen) _confirmAmountKeypad();
    final amount = _effectiveAmount;
    if (amount <= 0) {
      PlatformFeedback.showError(context, 'Enter a valid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      await _ensurePreviewResolved();
      await widget.onSave(amount, _editedDraft(), _effectiveImpact);
      if (mounted) {
        PlatformFeedback.mediumTap();
        Navigator.pop(context, true);
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
      key: _bodyKey,
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
        _FieldConfidenceWrap(
          lowConfidence: _merchantFieldLow,
          child: _editingVendor ? _vendorField() : _vendorLabel(),
        ),
        const SizedBox(height: 10),
        _MapPreview(
          loading: _previewLoading && _pickedPlace == null,
          place: _pickedPlace ?? _previewPlace,
          onTap: _openPlacePicker,
          mapOverride: widget.mapOverride,
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
        _FieldConfidenceWrap(
          lowConfidence: _amountFieldLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                key: const Key('receipt-amount-display'),
                onTap: _toggleAmountKeypad,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _amountDisplayLabel,
                  style: balooText(
                    38,
                    FontWeight.w800,
                    color: _amountKeypadOpen
                        ? ReceiptSheetColors.linkStrong
                        : ReceiptSheetColors.ink,
                    letterSpacing: -0.6,
                  ),
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
        const SizedBox(height: 14),
        Text('Note', style: balooText(13, FontWeight.w700, color: ReceiptSheetColors.subLight)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('receipt-note-field'),
          controller: _notesController,
          minLines: 1,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          style: balooText(14, FontWeight.w600, color: ReceiptSheetColors.ink),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: ReceiptSheetColors.tile,
            hintText: 'Dinner with friends',
            hintStyle: balooText(
              14,
              FontWeight.w500,
              color: ReceiptSheetColors.subLight.withValues(alpha: 0.6),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: ReceiptSheetColors.gold, width: 2),
            ),
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _DashedDivider(),
          const SizedBox(height: 14),
          Text(
            'Detected Items',
            style: balooText(
              13,
              FontWeight.w700,
              color: ReceiptSheetColors.subLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap an item to make changes',
            style: balooText(
              12,
              FontWeight.w600,
              color: ReceiptSheetColors.subLight.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _itemsMaxHeight),
            child: RawScrollbar(
              controller: _itemsScrollController,
              thumbVisibility:
                  _items.length * _itemRowExtentEstimate - 2 >
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
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, i) => _ItemRow(
                  index: i,
                  displayName: _names[i],
                  quantity: _quantities[i],
                  price: _prices[i],
                  checked: _checked[i],
                  editingPrice: _editingPriceIndex == i,
                  editingName: _editingNameIndex == i,
                  lowConfidence: (_items[i].confidence ?? 1.0) < 0.5,
                  priceController: _priceController,
                  priceFocus: _priceFocus,
                  nameController: _nameController,
                  nameFocus: _nameFocus,
                  nameFieldKey: _editingNameIndex == i ? _nameFieldKey : null,
                  priceFieldKey: _editingPriceIndex == i ? _priceFieldKey : null,
                  onToggle: () => _toggleItem(i),
                  onEditPrice: () => _startPriceEdit(i),
                  onEditName: () => _startNameEdit(i),
                  onEditQuantity: () => unawaited(_startQuantityEdit(i)),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    final actions = Column(
      key: _actionsKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (undoIndex != null) ...[
          _UndoBanner(
            itemLabel: _itemDisplayLabel(undoIndex),
            onUndo: _undoExclude,
          ),
          const SizedBox(height: 14),
        ],
        ReceiptSheetCta(
          label: 'Save',
          onPressed: _saving ? null : _save,
        ),
        const SizedBox(height: 8),
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
          // When the keyboard is up, AdaptiveSheet already pads by viewInsets,
          // so size the sheet against the remaining visible height — otherwise
          // the pinned Save CTA eats the Flexible viewport and the focused
          // item row stays scrolled out of sight under the keyboard.
          maxHeight: MediaQuery.viewInsetsOf(context).bottom > 0
              ? MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom
              : MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
          child: Builder(
            builder: (context) {
              final keyboardOpen =
                  MediaQuery.viewInsetsOf(context).bottom > 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ReceiptSheetHandle(),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _bodyScrollController,
                      // Extra bottom padding while editing so ensureVisible can
                      // park the focused field above the keyboard comfortably.
                      padding: EdgeInsets.only(
                        bottom: keyboardOpen ? 24 : 0,
                      ),
                      child: keyboardOpen
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                body,
                                const SizedBox(height: 20),
                                actions,
                              ],
                            )
                          : body,
                    ),
                  ),
                  if (!keyboardOpen) ...[
                    if (_amountKeypadOpen) ...[
                      const SizedBox(height: 12),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _AmountKeypad(
                          onDigit: _appendAmountDigit,
                          onBackspace: _backspaceAmountDigit,
                          onConfirm: _confirmAmountKeypad,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      const SizedBox(height: 20),
                      actions,
                    ],
                  ],
                ],
              );
            },
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
      key: const Key('receipt-vendor-field'),
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
/// Material-styled (not `balooText`/`ReceiptSheetColors`) — reused as-is rather
/// than re-skinned for this sheet.
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
    // app-wide (CategoryChip, transaction_list_tile.dart)
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
    required this.index,
    required this.displayName,
    required this.quantity,
    required this.price,
    required this.checked,
    required this.editingPrice,
    required this.editingName,
    required this.priceController,
    required this.priceFocus,
    required this.nameController,
    required this.nameFocus,
    required this.onToggle,
    required this.onEditPrice,
    required this.onEditName,
    required this.onEditQuantity,
    this.nameFieldKey,
    this.priceFieldKey,
    this.lowConfidence = false,
  });

  final int index;
  final String displayName;
  final int quantity;
  final double price;
  final bool checked;
  final bool editingPrice;
  final bool editingName;
  final bool lowConfidence;
  final TextEditingController priceController;
  final FocusNode priceFocus;
  final TextEditingController nameController;
  final FocusNode nameFocus;
  final Key? nameFieldKey;
  final Key? priceFieldKey;
  final VoidCallback onToggle;
  final VoidCallback onEditPrice;
  final VoidCallback onEditName;
  final VoidCallback onEditQuantity;

  @override
  Widget build(BuildContext context) {
    return _FieldConfidenceWrap(
      lowConfidence: lowConfidence,
      child: Row(
        children: [
          GestureDetector(
            key: Key('receipt-item-checkbox-$index'),
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
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
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Opacity(
              opacity: checked ? 1 : 0.4,
              // Inline swap — never stack a second name field under the label.
              child: editingName ? _nameField() : _nameLabel(),
            ),
          ),
          const SizedBox(width: 8),
          // Fixed-width column so ×1 / ×10 stay vertically aligned
          // across rows regardless of name length. 40×40 also meets
          // the minimum tap target for the quantity picker.
          GestureDetector(
            key: Key('receipt-item-quantity-$index'),
            onTap: onEditQuantity,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 40,
              height: 28,
              child: Align(
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: checked ? 1 : 0.4,
                  child: Text(
                    '×$quantity',
                    style: balooText(
                      13,
                      FontWeight.w600,
                      color: ReceiptSheetColors.subLight,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 78,
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
    return GestureDetector(
      onTap: onEditName,
      behavior: HitTestBehavior.opaque,
      child: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: balooText(
          15,
          FontWeight.w700,
          decoration: checked ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }

  Widget _nameField() {
    final field = TextField(
      key: const Key('receipt-item-name-field'),
      controller: nameController,
      focusNode: nameFocus,
      autofocus: true,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => nameFocus.unfocus(),
      cursorColor: ReceiptSheetColors.gold,
      // Leave room below the caret so ensureVisible parks this above the
      // keyboard rather than flush against it.
      scrollPadding: const EdgeInsets.only(bottom: 120),
      style: balooText(
        15,
        FontWeight.w700,
        decoration: checked ? null : TextDecoration.lineThrough,
      ),
      // Soft cream fill + gold edge so the whole name reads as selected
      // and ready to overwrite the moment the keyboard opens.
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
    return GestureDetector(
      onTap: onEditPrice,
      behavior: HitTestBehavior.opaque,
      child: Opacity(
        opacity: checked ? 1 : 0.4,
        child: Text(
          'RM ${price.toStringAsFixed(2)}',
          textAlign: TextAlign.right,
          style: balooText(15, FontWeight.w700),
        ),
      ),
    );
  }

  Widget _priceField() {
    const goldUnderline = UnderlineInputBorder(
      borderSide: BorderSide(color: ReceiptSheetColors.gold, width: 2),
    );
    final field = TextField(
      key: const Key('receipt-price-field'),
      controller: priceController,
      focusNode: priceFocus,
      autofocus: true,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => priceFocus.unfocus(),
      cursorColor: ReceiptSheetColors.gold,
      scrollPadding: const EdgeInsets.only(bottom: 120),
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
    );
    if (priceFieldKey == null) return field;
    return KeyedSubtree(key: priceFieldKey, child: field);
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

const _mapPreviewHeight = 80.0;

/// Small tappable map preview shown below the merchant row — replaces the
/// old pencil-icon button. Purely a visual thumbnail (the `GoogleMap` is
/// gesture-disabled and `IgnorePointer`-wrapped); the surrounding
/// [GestureDetector] is the single source of the tap that opens the location
/// picker, in every state (loading / resolved / no-location), matching what
/// the old pencil button used to do.
class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.loading,
    required this.place,
    required this.onTap,
    this.mapOverride,
  });

  final bool loading;
  final PlaceResult? place;
  final VoidCallback onTap;
  final Widget? mapOverride;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _mapPreviewHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: ReceiptSheetColors.tile,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _content(),
            Positioned(right: 8, bottom: 8, child: _editBadge()),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (loading) return _loadingState();
    final p = place;
    if (p == null) return _emptyState();
    // Keyed by the resolved coordinates so a later change of `place` (e.g.
    // the auto-resolved guess being superseded by an explicit user pick)
    // forces GoogleMap to be re-created rather than silently keeping its
    // stale initial camera position — GoogleMap ignores post-creation
    // changes to `initialCameraPosition`.
    return IgnorePointer(
      child: mapOverride ??
          GoogleMap(
            key: ValueKey('map-preview-${p.lat}-${p.lng}'),
            initialCameraPosition:
                CameraPosition(target: LatLng(p.lat, p.lng), zoom: 15),
            markers: {
              Marker(
                markerId: MarkerId(p.id.isEmpty ? p.name : p.id),
                position: LatLng(p.lat, p.lng),
              ),
            },
            zoomControlsEnabled: false,
            zoomGesturesEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
          ),
    );
  }

  Widget _loadingState() {
    return const Center(
      child: SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: ReceiptSheetColors.gold,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off_outlined,
            size: 20,
            color: ReceiptSheetColors.subLight,
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to set location',
            style: balooText(
              12,
              FontWeight.w600,
              color: ReceiptSheetColors.subLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _editBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ReceiptSheetColors.sheetShadow,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(
        Icons.edit_location_outlined,
        size: 14,
        color: ReceiptSheetColors.sub,
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

/// Banking-style numeric keypad for the receipt total. Digits append from the
/// right into a cents buffer (handled by the parent); Confirm freezes the
/// amount and collapses the pad.
class _AmountKeypad extends StatelessWidget {
  const _AmountKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onConfirm,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onConfirm;

  static const _rows = <List<Object>>[
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
    ['backspace', 0, 'confirm'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('receipt-amount-keypad'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < _rows.length; r++) ...[
          if (r > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var c = 0; c < _rows[r].length; c++) ...[
                if (c > 0) const SizedBox(width: 8),
                Expanded(child: _keyFor(_rows[r][c])),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _keyFor(Object key) {
    if (key is int) {
      return _AmountKeypadKey(
        key: Key('receipt-amount-keypad-digit-$key'),
        onTap: () => onDigit(key),
        child: Text(
          '$key',
          style: balooText(
            22,
            FontWeight.w800,
            color: ReceiptSheetColors.ink,
          ),
        ),
      );
    }
    if (key == 'backspace') {
      return _AmountKeypadKey(
        key: const Key('receipt-amount-keypad-backspace'),
        onTap: onBackspace,
        child: const Icon(
          Icons.backspace_outlined,
          size: 22,
          color: ReceiptSheetColors.ink,
        ),
      );
    }
    return _AmountKeypadKey(
      key: const Key('receipt-amount-keypad-confirm'),
      onTap: onConfirm,
      filled: true,
      child: Text(
        'OK',
        style: balooText(
          16,
          FontWeight.w800,
          color: ReceiptSheetColors.ctaText,
        ),
      ),
    );
  }
}

class _AmountKeypadKey extends StatelessWidget {
  const _AmountKeypadKey({
    super.key,
    required this.onTap,
    required this.child,
    this.filled = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? ReceiptSheetColors.gold : ReceiptSheetColors.tile,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 48,
          child: Center(child: child),
        ),
      ),
    );
  }
}
