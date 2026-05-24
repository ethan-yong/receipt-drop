import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/amount_field.dart';
import '../../widgets/place_block.dart';
import '../../widgets/puggy_primary_button.dart';
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
  DateTime? _occurredAt;
  bool _loading = true;

  static const _categories = [
    'Food & Drink',
    'Groceries',
    'Transport',
    'Shopping',
    'Others',
    'Unclassified',
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tx = await AppServices.transactions.getById(widget.transactionId);
    if (tx == null || !mounted) return;
    setState(() {
      _amountController.text =
          tx.amountMyr?.toStringAsFixed(2) ?? '';
      _category = tx.effectiveCategory;
      _placeName = tx.displayPlace;
      _occurredAt = tx.occurredAt;
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
    final updated = tx.copyWith(
      amountMyr: parsed,
      needsAmount: parsed == null,
      categoryUser: _category,
      placeName: _placeName == 'No place' ? null : _placeName,
      occurredAt: _occurredAt,
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
    final result = await context.pushNamed<String>('places-search');
    if (result != null && mounted) {
      setState(() => _placeName = result);
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
                  items: _categories
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
            PuggyPrimaryButton(label: 'Save changes', onPressed: _save),
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
