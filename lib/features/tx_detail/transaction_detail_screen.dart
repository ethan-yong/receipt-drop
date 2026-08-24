import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/bill_split_repository.dart';
import '../../data/repositories/places_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/logic/impact_level.dart';
import '../../domain/models/bill_split.dart';
import '../../domain/models/receipt_display_image.dart';
import '../../domain/models/receipt_line_item.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/places/place_picker_screen.dart';
import '../../features/share/receipt_retake_flow.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/place_block.dart';
import '../../widgets/quantity_picker_sheet.dart';
import '../../widgets/receipt_drop_primary_button.dart';
import '../../widgets/receipt_line_item_row.dart';
import '../../widgets/receipt_thumbnail.dart';
import '../../widgets/skeleton.dart';
import '../bill_split/bill_split_sheet.dart';
import 'receipt_image_viewer_screen.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    this.editable = false,
  });

  final String transactionId;

  /// When false (default), the screen is view-only: no item/place edits and
  /// no Save / Split actions. Home opens with [editable] true.
  final bool editable;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final _amountController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _nameFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _nameFieldKey = GlobalKey();
  final _priceFieldKey = GlobalKey();

  String? _category;
  String _placeName = 'No place';
  String? _placeGooglePlaceId;
  double? _placeLat;
  double? _placeLng;
  double? _shareLocationLat;
  double? _shareLocationLng;
  DateTime? _occurredAt;
  ImpactLevel? _impactOverride;
  bool _loading = true;
  CategoryConfig? _categoryConfig;
  List<ReceiptLineItem> _lineItems = const [];
  ReceiptDisplayImage? _displayImage;
  bool _needsReview = false;
  bool _resolvingImage = false;
  bool _amountManuallyEdited = false;
  int? _editingNameIndex;
  int? _editingPriceIndex;

  /// By-item split assignees for the Items column layout (same as map sheet).
  BillSplitView? _split;
  List<FriendshipView> _friends = const [];
  String? _ownerId;
  String? _ownerDisplayName;
  String? _ownerAvatarUrl;

  /// In-page confirmation after Save (never navigates away).
  bool _showSavedBanner = false;
  bool _showSplitStaleBanner = false;
  bool _remindingFriends = false;

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _nameFocus.dispose();
    _priceFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ownerId =
        Env.hasSupabaseConfig ? Supabase.instance.client.auth.currentUser?.id : null;
    final results = await Future.wait([
      AppServices.transactions.getById(widget.transactionId),
      loadBundledCategoryConfig(),
      BillSplitRepository.getSplitForTransaction(widget.transactionId),
      SocialRepository.listFriendships(),
      if (ownerId != null) ProfileRepository.fetchProfileHeader(ownerId),
    ]);
    final tx = results[0] as TransactionView?;
    final config = results[1] as CategoryConfig;
    final split = results[2] as BillSplitView?;
    final friends = results[3] as List<FriendshipView>;
    final ownerHeader = ownerId != null
        ? results[4] as ({String? displayName, String? username, String? avatarUrl})
        : null;
    if (tx == null || !mounted) return;
    setState(() {
      _amountController.text = tx.amountMyr?.toStringAsFixed(2) ?? '';
      _category = tx.effectiveCategory;
      _placeName = tx.displayPlace;
      _placeGooglePlaceId = tx.placeGooglePlaceId;
      _placeLat = tx.placeLat;
      _placeLng = tx.placeLng;
      _shareLocationLat = tx.shareLocationLat;
      _shareLocationLng = tx.shareLocationLng;
      _occurredAt = tx.occurredAt;
      _impactOverride = impactLevelFromStorage(tx.impactUser);
      _categoryConfig = config;
      _lineItems = List<ReceiptLineItem>.from(tx.lineItems ?? const []);
      _needsReview = tx.needsReview;
      _split = split;
      _friends =
          friends.where((f) => f.status == FriendshipStatus.accepted).toList();
      _ownerId = ownerId;
      _ownerDisplayName = ownerHeader?.displayName;
      _ownerAvatarUrl = ownerHeader?.avatarUrl;
      _amountManuallyEdited = false;
      _editingNameIndex = null;
      _editingPriceIndex = null;
      _loading = false;
      _resolvingImage = true;
    });
    await _resolveImage();
  }

  List<String> _assigneesFor(ReceiptLineItem item) {
    final split = _split;
    if (split == null) return const [];
    return split.assigneeIdsForLineItem(item.id);
  }

  /// [personKey] is a [BillSplitParticipant.personKey] — a friend's
  /// `profiles.id`, or (for an external phone contact) that participant's
  /// own row id, resolved below via `_split.participants`.
  String? _displayNameFor(String personKey) {
    if (personKey == _ownerId) return _ownerDisplayName ?? 'You';
    for (final f in _friends) {
      if (f.otherUserId == personKey) return f.otherDisplayName;
    }
    return _split?.participants
        .where((p) => p.isExternalContact && p.id == personKey)
        .firstOrNull
        ?.contactName;
  }

  String? _avatarUrlFor(String personKey) {
    if (personKey == _ownerId) return _ownerAvatarUrl;
    for (final f in _friends) {
      if (f.otherUserId == personKey) return f.otherAvatarUrl;
    }
    return null; // external contacts have no avatar
  }

  Future<void> _resolveImage() async {
    final image = await AppServices.transactions.resolveDisplayImage(
      widget.transactionId,
    );
    if (!mounted) return;
    setState(() {
      _displayImage = image;
      _resolvingImage = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _priceFocus.addListener(() {
      if (!_priceFocus.hasFocus && _editingPriceIndex != null) {
        _commitPriceEdit();
      }
    });
    _nameFocus.addListener(() {
      if (!_nameFocus.hasFocus && _editingNameIndex != null) {
        _commitNameEdit();
      }
    });
    _load();
  }

  void _onAmountChanged(String _) {
    _amountManuallyEdited = true;
  }

  void _syncAmountFromItems() {
    if (_amountManuallyEdited) return;
    if (_lineItems.isEmpty) return;
    final total = _lineItems.fold<double>(0, (sum, item) => sum + item.priceMyr);
    _amountController.text = total.toStringAsFixed(2);
  }

  void _commitAllPendingEdits() {
    if (_editingPriceIndex != null) _commitPriceEdit();
    if (_editingNameIndex != null) _commitNameEdit();
  }

  void _startNameEdit(int index) {
    _commitAllPendingEdits();
    setState(() {
      _editingNameIndex = index;
      _nameController.text = _lineItems[index].name;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingNameIndex != index) return;
      _nameFocus.requestFocus();
      _nameController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _nameController.text.length,
      );
    });
  }

  void _commitNameEdit() {
    final index = _editingNameIndex;
    if (index == null) return;
    final text = _nameController.text.trim();
    setState(() {
      if (text.isNotEmpty) {
        _lineItems = [
          for (var i = 0; i < _lineItems.length; i++)
            if (i == index) _lineItems[i].copyWith(name: text) else _lineItems[i],
        ];
      }
      _editingNameIndex = null;
    });
  }

  void _startPriceEdit(int index) {
    _commitAllPendingEdits();
    setState(() {
      _editingPriceIndex = index;
      _priceController.text = _lineItems[index].priceMyr.toStringAsFixed(2);
      _priceController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _priceController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingPriceIndex != index) return;
      _priceFocus.requestFocus();
    });
  }

  void _commitPriceEdit() {
    final index = _editingPriceIndex;
    if (index == null) return;
    final parsed =
        double.tryParse(_priceController.text.trim().replaceAll(',', ''));
    setState(() {
      if (parsed != null && parsed >= 0) {
        _lineItems = [
          for (var i = 0; i < _lineItems.length; i++)
            if (i == index)
              _lineItems[i].copyWith(priceMyr: parsed)
            else
              _lineItems[i],
        ];
      }
      _editingPriceIndex = null;
      _syncAmountFromItems();
    });
  }

  Future<void> _startQuantityEdit(int index) async {
    _commitAllPendingEdits();
    final item = _lineItems[index];
    final result = await AdaptiveSheet.showForm<int>(
      context: context,
      backgroundColor: ReceiptSheetColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: QuantityPickerSheet(
        itemName: item.name,
        initialQuantity: item.quantity ?? 1,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _lineItems = [
        for (var i = 0; i < _lineItems.length; i++)
          if (i == index) _lineItems[i].copyWith(quantity: result) else _lineItems[i],
      ];
      _syncAmountFromItems();
    });
  }

  Future<void> _openViewer() async {
    final image = _displayImage;
    if (image == null || !image.isAvailable) return;
    await ReceiptImageViewerScreen.push(
      context,
      image: image,
      onRetake: () {
        // Defer so the viewer finishes popping before the capture menu opens.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _startRetake();
        });
      },
    );
  }

  Future<void> _startRetake() async {
    final replaced = await ReceiptRetakeFlow.start(
      context,
      transactionId: widget.transactionId,
    );
    if (replaced && mounted) {
      setState(() => _loading = true);
      await _load();
    }
  }

  /// Pop when opened from history/map; otherwise land Home (e.g. after
  /// post-save View receipt used `goNamed` and left no stack).
  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('home');
    }
  }

  bool _lineItemsAffectSplit(
    List<ReceiptLineItem> before,
    List<ReceiptLineItem> after,
  ) {
    final prevById = {
      for (final i in before)
        if (i.id != null) i.id!: (price: i.priceMyr, qty: i.quantity),
    };
    for (final item in after) {
      final id = item.id;
      if (id == null) continue;
      final prev = prevById[id];
      if (prev == null) continue;
      if (prev.price != item.priceMyr || prev.qty != item.quantity) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    _commitAllPendingEdits();
    final tx = await AppServices.transactions.getById(widget.transactionId);
    if (tx == null) return;
    final previousAmount = tx.amountMyr;
    final previousItems = tx.lineItems ?? const <ReceiptLineItem>[];
    final parsed = double.tryParse(_amountController.text.trim());
    final autoImpact = deriveImpactLevel(parsed);
    final impact = _impactOverride ?? autoImpact;
    final updated = tx.copyWith(
      amountMyr: parsed,
      needsAmount: parsed == null,
      categoryUser: _category,
      placeName: _placeName == 'No place' ? null : _placeName,
      placeGooglePlaceId: _placeGooglePlaceId,
      placeLat: _placeLat,
      placeLng: _placeLng,
      occurredAt: _occurredAt,
      impactUser: impact.storageValue,
      lineItems: _lineItems,
    );
    await AppServices.transactions.updateTransaction(updated);

    final amountChanged = previousAmount != parsed;
    final itemsChanged = _lineItemsAffectSplit(previousItems, _lineItems);
    var splitStale = false;
    if (parsed != null && (amountChanged || itemsChanged)) {
      final existing = await BillSplitRepository.getSplitForTransaction(
        widget.transactionId,
      );
      if (existing != null) {
        final recalc = await BillSplitRepository.recalculateShares(
          transactionId: widget.transactionId,
          totalMyr: parsed,
          lineItems: [
            for (final i in _lineItems)
              if (i.id != null) (id: i.id!, priceMyr: i.priceMyr),
          ],
        );
        splitStale = recalc != null;
      }
    }

    if (!mounted) return;
    setState(() {
      _showSavedBanner = true;
      _showSplitStaleBanner = splitStale;
    });
    await _load();
  }

  Future<void> _remindFriendsFromBanner() async {
    final split = _split;
    if (split == null || _remindingFriends) return;
    final pending = split.participants.where((p) => !p.paid).toList();
    if (pending.isEmpty) {
      setState(() => _showSplitStaleBanner = false);
      return;
    }
    setState(() => _remindingFriends = true);
    await Future.wait(
      pending.map((p) => BillSplitRepository.sendReminder(p.id)),
    );
    if (!mounted) return;
    setState(() {
      _remindingFriends = false;
      _showSplitStaleBanner = false;
    });
  }

  Future<void> _openBillSplit() async {
    await BillSplitSheet.show(
      context,
      transactionId: widget.transactionId,
      afterCommit: BillSplitAfterCommit.stay,
    );
    if (mounted) await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await AppServices.transactions.deleteTransaction(widget.transactionId);
      if (mounted) _leave();
    }
  }

  Future<void> _pickPlace() async {
    // Prefer the resolved place's coordinates (set for almost any synced/
    // enriched transaction) over the share-time capture location, which is
    // only available when location permission was granted at share time.
    final lat = _placeLat ?? _shareLocationLat;
    final lng = _placeLng ?? _shareLocationLng;
    PlaceResult? result;
    if (lat != null && lng != null) {
      result = await PlacePickerScreen.push(
        context,
        lat: lat,
        lng: lng,
        candidates: const [],
        merchantName: _placeName == 'No place' ? null : _placeName,
        category: _category,
      );
    } else {
      result = await context.pushNamed<PlaceResult>('places-search');
    }
    if (result == null || !mounted) return;
    await AppServices.transactions
        .updateTransactionPlace(widget.transactionId, result);
    setState(() {
      _placeName = result!.name;
      _placeGooglePlaceId = result.id;
      _placeLat = result.lat;
      _placeLng = result.lng;
    });
  }

  Future<void> _pickDate() async {
    final base = _occurredAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time != null) {
      setState(() {
        _occurredAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
      });
    }
  }

  List<String> _buildCategoryItems() {
    final config = _categoryConfig;
    if (config == null) return [_category ?? 'Unclassified'];
    return {
      ...config.rules.map((r) => r.category),
      config.defaultCategory,
      'Unclassified',
    }.toList();
  }

  Widget _buildThumbnailSection() {
    final image = _displayImage;
    final available = image?.isAvailable ?? false;

    final Widget thumb;
    if (_resolvingImage) {
      thumb = const Skeleton(
        child: AspectRatio(
          aspectRatio: 1 / 0.86,
          child: SkeletonBox(
            width: double.infinity,
            height: double.infinity,
            radius: AppSpacing.heroRadius,
          ),
        ),
      );
    } else if (!available) {
      thumb = _AddPhotoPlaceholder(onTap: _startRetake);
    } else {
      thumb = AspectRatio(
        aspectRatio: 1 / 0.86,
        child: ReceiptThumbnail(
          width: double.infinity,
          height: double.infinity,
          radius: AppSpacing.heroRadius,
          localPath: image?.localPath,
          imageUrl: image?.imageUrl,
        ),
      );
    }

    final framed = available || _resolvingImage
        ? Container(
            decoration: BoxDecoration(
              borderRadius: AppSpacing.heroBorderRadius,
              border: Border.all(color: AppColors.divider, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.textPrimary.withValues(alpha: 0.10),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: thumb,
          )
        : thumb;

    return Column(
      children: [
        if (available)
          GestureDetector(
            onTap: _openViewer,
            child: framed,
          )
        else
          framed,
        if (_needsReview) ...[
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: available ? _openViewer : null,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.12),
                borderRadius: AppSpacing.chipBorderRadius,
              ),
              child: Text(
                'check this scan',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: SafeArea(child: _TxDetailSkeleton()),
      );
    }

    final dateLabel = _occurredAt != null
        ? DateFormat('EEE, d MMM · HH:mm').format(_occurredAt!)
        : '';

    final parsedAmount = double.tryParse(_amountController.text.trim());
    final effectiveImpact = _impactOverride ?? deriveImpactLevel(parsedAmount);
    final editable = widget.editable;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          // From receipt-saved we `goNamed` here (no stack to pop) — land home.
          onPressed: _leave,
        ),
        title: const Text('Transaction'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showSavedBanner) ...[
              _SavedConfirmationBanner(
                splitStale: _showSplitStaleBanner,
                reminding: _remindingFriends,
                onRemind: _remindFriendsFromBanner,
                onDismiss: () => setState(() {
                  _showSavedBanner = false;
                  _showSplitStaleBanner = false;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            // Extracted fields stay primary; photo is a verification affordance.
            Center(child: _buildThumbnailSection()),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: AmountField(
                  controller: _amountController,
                  onChanged: editable ? _onAmountChanged : null,
                  readOnly: !editable,
                ),
              ),
            ),
            if (_lineItems.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Items',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var i = 0; i < _lineItems.length; i++)
                        ReceiptLineItemRow(
                          item: _lineItems[i],
                          assigneeIds: _assigneesFor(_lineItems[i]),
                          displayNameFor: _displayNameFor,
                          avatarUrlFor: _avatarUrlFor,
                          textStyle:
                              Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle(),
                          bottomPadding: 6,
                          editingName:
                              editable && _editingNameIndex == i,
                          editingPrice:
                              editable && _editingPriceIndex == i,
                          nameController: _nameController,
                          nameFocus: _nameFocus,
                          priceController: _priceController,
                          priceFocus: _priceFocus,
                          nameFieldKey: editable && _editingNameIndex == i
                              ? _nameFieldKey
                              : null,
                          priceFieldKey: editable && _editingPriceIndex == i
                              ? _priceFieldKey
                              : null,
                          onEditName:
                              editable ? () => _startNameEdit(i) : null,
                          onEditPrice:
                              editable ? () => _startPriceEdit(i) : null,
                          onEditQuantity: editable
                              ? () => unawaited(_startQuantityEdit(i))
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text('Impact', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (final level in ImpactLevel.values) ...[
                  if (level != ImpactLevel.values.first)
                    const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ImpactChip(
                      level: level,
                      selected: effectiveImpact == level,
                      onTap: editable
                          ? () => setState(() => _impactOverride = level)
                          : null,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            PlaceBlock(
              placeName: _placeName,
              lat: _placeLat,
              lng: _placeLng,
              onChangePlace: editable ? _pickPlace : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: InputBorder.none,
                    filled: false,
                  ),
                  items: _buildCategoryItems()
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: editable
                      ? (v) => setState(() => _category = v)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                title: const Text('Date & time'),
                subtitle: Text(dateLabel),
                trailing: editable ? const Icon(Icons.chevron_right) : null,
                onTap: editable ? _pickDate : null,
              ),
            ),
            if (editable) ...[
              const SizedBox(height: AppSpacing.xl),
              ReceiptDropPrimaryButton(label: 'Save changes', onPressed: _save),
              const SizedBox(height: AppSpacing.md),
              if (_split != null) ...[
                _SplitSharesSummary(
                  split: _split!,
                  displayNameFor: _displayNameFor,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              OutlinedButton.icon(
                onPressed: parsedAmount != null ? _openBillSplit : null,
                icon: const Icon(Icons.call_split),
                label: Text(_split == null ? 'Split this bill' : 'View split'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: _delete,
                child: const Text(
                  'Delete transaction',
                  style: TextStyle(color: AppColors.destructive),
                ),
              ),
            ] else if (_split != null) ...[
              const SizedBox(height: AppSpacing.xl),
              _SplitSharesSummary(
                split: _split!,
                displayNameFor: _displayNameFor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedConfirmationBanner extends StatelessWidget {
  const _SavedConfirmationBanner({
    required this.splitStale,
    required this.reminding,
    required this.onRemind,
    required this.onDismiss,
  });

  final bool splitStale;
  final bool reminding;
  final VoidCallback onRemind;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.primaryGreen.withValues(alpha: 0.12),
      borderRadius: AppSpacing.cardBorderRadius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.check_circle,
                color: AppColors.primaryGreenDark,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Changes saved.',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (splitStale) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Your friends may have outdated split amounts.',
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: reminding ? null : onRemind,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryGreenDark,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(reminding ? 'Sending…' : 'Remind friends'),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.textMuted,
              onPressed: onDismiss,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitSharesSummary extends StatelessWidget {
  const _SplitSharesSummary({
    required this.split,
    required this.displayNameFor,
  });

  final BillSplitView split;
  final String? Function(String userId) displayNameFor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Split shares', style: textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            _shareRow(
              context,
              label: 'You',
              amount: split.yourShareMyr,
            ),
            for (final p in split.participants)
              _shareRow(
                context,
                label: displayNameFor(p.personKey) ??
                    (p.isExternalContact ? (p.contactName ?? 'Contact') : 'Friend'),
                amount: p.shareMyr,
                paid: p.paid,
              ),
          ],
        ),
      ),
    );
  }

  Widget _shareRow(
    BuildContext context, {
    required String label,
    required double amount,
    bool paid = false,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              paid ? '$label (paid)' : label,
              style: textTheme.bodyMedium,
            ),
          ),
          Text(
            'RM ${amount.toStringAsFixed(2)}',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _TxDetailSkeleton extends StatelessWidget {
  const _TxDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AspectRatio(
              aspectRatio: 1 / 0.86,
              child: SkeletonBox(
                width: double.infinity,
                height: double.infinity,
                radius: AppSpacing.heroRadius,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: const SkeletonBox(width: 140, height: 40),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SkeletonBox(width: 60, height: 12),
                    const SizedBox(height: AppSpacing.sm),
                    for (var i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      Row(
                        children: const [
                          Expanded(child: SkeletonBox(height: 12)),
                          SizedBox(width: AppSpacing.sm),
                          SkeletonBox(width: 40, height: 12),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const SkeletonBox(width: 60, height: 14),
            const SizedBox(height: AppSpacing.sm),
            const Row(
              children: [
                Expanded(
                    child:
                        SkeletonBox(height: 40, radius: AppSpacing.chipRadius)),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                    child:
                        SkeletonBox(height: 40, radius: AppSpacing.chipRadius)),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                    child:
                        SkeletonBox(height: 40, radius: AppSpacing.chipRadius)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: const SkeletonBox(width: double.infinity, height: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: const SkeletonBox(width: double.infinity, height: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: const SkeletonBox(width: double.infinity, height: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoPlaceholder extends StatelessWidget {
  const _AddPhotoPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Add receipt photo',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.heroBorderRadius,
          child: CustomPaint(
            painter: _DottedRRectPainter(
              color: AppColors.divider,
              borderRadius: AppSpacing.heroRadius,
            ),
            child: const AspectRatio(
              aspectRatio: 1 / 0.86,
              child: Center(
                child: Icon(
                  Icons.add_rounded,
                  size: 48,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedRRectPainter extends CustomPainter {
  const _DottedRRectPainter({
    required this.color,
    required this.borderRadius,
  });

  final Color color;
  final double borderRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const dashLength = 3.0;
    const gapLength = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
}

class _ImpactChip extends StatelessWidget {
  const _ImpactChip({
    required this.level,
    required this.selected,
    this.onTap,
  });

  final ImpactLevel level;
  final bool selected;
  final VoidCallback? onTap;

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

  static final _pillRadius = BorderRadius.circular(999);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: _pillRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _color : AppColors.cardSurface,
          borderRadius: _pillRadius,
          border: Border.all(
            color: selected ? _color : AppColors.divider,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          level.label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
