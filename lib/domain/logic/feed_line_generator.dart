import '../models/transaction_view.dart';
import 'impact_level.dart';

const _impactAdj = {
  ImpactLevel.low: 'Low-key',
  ImpactLevel.med: 'Mid-tier',
  ImpactLevel.high: 'High-impact',
};

const _categoryNoun = {
  'Food & Drink': 'lunch',
  'Groceries': 'grocery run',
  'Transport': 'transport spend',
  'Shopping': 'shopping trip',
  'Unclassified': 'receipt drop',
};

/// Privacy-safe feed line: impact tier + category + place — never RM amounts.
/// Called once at save time; result is persisted in `feed_posts.line`.
String generateFeedLine(TransactionView transaction) {
  final impact = _impactAdj[transaction.effectiveImpactLevel] ?? 'Mid-tier';
  final category = transaction.effectiveCategory;
  final noun = _categoryNoun[category] ?? category.toLowerCase();
  final place = _placeLabel(transaction);

  if (place == null) {
    return '$impact $noun';
  }
  return '$impact $noun at $place';
}

String? _placeLabel(TransactionView transaction) {
  final name = transaction.placeName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final merchant = transaction.merchantRaw?.trim();
  if (merchant != null && merchant.isNotEmpty) return merchant;
  return null;
}
