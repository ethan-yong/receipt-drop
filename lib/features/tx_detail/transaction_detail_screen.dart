import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/transaction_view.dart';
import '../../data/repositories/places_repository.dart';
import '../../domain/logic/category_matcher.dart';
import '../../domain/logic/category_matcher_bundled.dart';
import '../../domain/logic/impact_level.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/place_block.dart';
import '../../widgets/receipt_drop_primary_button.dart';
import '../../widgets/receipt_strip.dart';
import '../../widgets/receipt_thumbnail.dart';

class TransactionDetailScreen extends StatefulWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  State<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends State<TransactionDetailScreen> {
  final _amountController = TextEditingController();
  String? _category;
  String _placeName = 'No place';
  String? _placeGooglePlaceId;
  double? _placeLat;
  double? _placeLng;
  DateTime? _occurredAt;
  ImpactLevel? _impactOverride;
  bool _loading = true;
  CategoryConfig? _categoryConfig;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      AppServices.transactions.getById(widget.transactionId),
      loadBundledCategoryConfig(),
    ]);
    final tx = results[0] as TransactionView?;
    final config = results[1] as CategoryConfig;
    if (tx == null || !mounted) return;
    setState(() {
      _amountController.text = tx.amountMyr?.toStringAsFixed(2) ?? '';
      _category = tx.effectiveCategory;
      _placeName = tx.displayPlace;
      _placeGooglePlaceId = tx.placeGooglePlaceId;
      _placeLat = tx.placeLat;
      _placeLng = tx.placeLng;
      _occurredAt = tx.occurredAt;
      _impactOverride = impactLevelFromStorage(tx.impactUser);
      _categoryConfig = config;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _save() async {
    final tx = await AppServices.transactions.getById(widget.transactionId);
    if (tx == null) return;
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
    );
    await AppServices.transactions.updateTransaction(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved')),
      );
      context.pop();
    }
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
      if (mounted) context.pop();
    }
  }

  Future<void> _pickPlace() async {
    final result = await context.pushNamed<PlaceResult>('places-search');
    if (result != null && mounted) {
      setState(() {
        _placeName = result.name;
        _placeGooglePlaceId = result.id;
        _placeLat = result.lat;
        _placeLng = result.lng;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dateLabel = _occurredAt != null
        ? DateFormat('EEE, d MMM · HH:mm').format(_occurredAt!)
        : '';

    final parsedAmount = double.tryParse(_amountController.text.trim());
    final effectiveImpact = _impactOverride ?? deriveImpactLevel(parsedAmount);

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Transaction'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: ReceiptThumbnail(size: 200, radius: AppSpacing.cardRadius),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: AppSpacing.cardPadding,
                child: AmountField(controller: _amountController),
              ),
            ),
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
                      onTap: () => setState(() => _impactOverride = level),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(child: ReceiptStrip(impact: effectiveImpact)),
            const SizedBox(height: AppSpacing.md),
            PlaceBlock(
              placeName: _placeName,
              onChangePlace: _pickPlace,
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
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                title: const Text('Date & time'),
                subtitle: Text(dateLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            ReceiptDropPrimaryButton(label: 'Save changes', onPressed: _save),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: _delete,
              child: const Text(
                'Delete transaction',
                style: TextStyle(color: AppColors.destructive),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
        ),
      ),
    );
  }
}
