import 'package:uuid/uuid.dart';

import '../../domain/models/transaction_view.dart';

/// Shared demo seed rows (native Drift + web in-memory).
List<TransactionView> demoTransactions({String userId = 'demo-user'}) {
  final now = DateTime.now();
  final demos = <({
    double? amount,
    bool needsAmount,
    String merchant,
    String category,
    String place,
    double lat,
    double lng,
    String sync,
    Duration ago,
  })>[
    (
      amount: 12.50,
      needsAmount: false,
      merchant: '7-Eleven Sunway',
      category: 'Food & Drink',
      place: '7-Eleven Sunway',
      lat: 3.0738,
      lng: 101.6067,
      sync: 'synced',
      ago: const Duration(hours: 2),
    ),
    (
      amount: 8.90,
      needsAmount: false,
      merchant: 'Tealive SS15',
      category: 'Food & Drink',
      place: 'Tealive SS15',
      lat: 3.0762,
      lng: 101.5854,
      sync: 'synced',
      ago: const Duration(hours: 5),
    ),
    (
      amount: 45.00,
      needsAmount: false,
      merchant: 'Village Grocer',
      category: 'Groceries',
      place: 'Village Grocer',
      lat: 3.1123,
      lng: 101.6549,
      sync: 'synced',
      ago: const Duration(days: 1, hours: 3),
    ),
    (
      amount: null,
      needsAmount: true,
      merchant: 'Unknown merchant',
      category: 'Unclassified',
      place: 'No place',
      lat: 3.1390,
      lng: 101.6869,
      sync: 'synced',
      ago: const Duration(days: 1, hours: 8),
    ),
    (
      amount: 22.40,
      needsAmount: false,
      merchant: 'Shell Damansara',
      category: 'Transport',
      place: 'Shell Damansara',
      lat: 3.1357,
      lng: 101.6180,
      sync: 'synced',
      ago: const Duration(days: 2),
    ),
    (
      amount: 156.80,
      needsAmount: false,
      merchant: 'AEON Big',
      category: 'Groceries',
      place: 'AEON Big',
      lat: 3.0489,
      lng: 101.6201,
      sync: 'synced',
      ago: const Duration(days: 5),
    ),
    (
      amount: 6.50,
      needsAmount: false,
      merchant: 'MyNews',
      category: 'Food & Drink',
      place: 'MyNews',
      lat: 3.0899,
      lng: 101.5950,
      sync: 'synced',
      ago: const Duration(days: 6),
    ),
  ];

  return [
    for (final d in demos)
      TransactionView(
        id: const Uuid().v4(),
        occurredAt: now.subtract(d.ago),
        amountMyr: d.amount,
        needsAmount: d.needsAmount,
        merchantRaw: d.merchant,
        categoryGuess: d.category,
        categoryUser: null,
        placeName: d.place == 'No place' ? null : d.place,
        placeGooglePlaceId: null,
        placeLat: d.lat,
        placeLng: d.lng,
        syncStatus: d.sync,
        pipelineStatus: 'provisional',
        localThumbnailPath: null,
      ),
  ];
}

/// Categories covered by [receiptShowcaseTransactions].
const kReceiptShowcaseCategories = [
  'Cafe',
  'Restaurant',
  'Grocery',
  'Clothing',
  'Tech',
];

bool hasFullReceiptShowcase(List<TransactionView> todayRows) {
  final categories = todayRows.map((t) => t.effectiveCategory).toSet();
  return kReceiptShowcaseCategories.every(categories.contains);
}

/// Fixed-ID today rows for the home receipt carousel (one per card palette).
List<TransactionView> receiptShowcaseTransactions({String userId = 'demo-user'}) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  DateTime at(int hour, int minute) =>
      today.add(Duration(hours: hour, minutes: minute));

  const showcases = <({
    String id,
    String merchant,
    String category,
    double amount,
    int hour,
    int minute,
  })>[
    (
      id: 'showcase-receipt-cafe',
      merchant: 'Brew & Co.',
      category: 'Cafe',
      amount: 27.30,
      hour: 10,
      minute: 42,
    ),
    (
      id: 'showcase-receipt-restaurant',
      merchant: 'The Copper Pot',
      category: 'Restaurant',
      amount: 59.50,
      hour: 19,
      minute: 28,
    ),
    (
      id: 'showcase-receipt-grocery',
      merchant: 'FreshMart',
      category: 'Grocery',
      amount: 34.50,
      hour: 17,
      minute: 14,
    ),
    (
      id: 'showcase-receipt-clothing',
      merchant: 'Thread & Co.',
      category: 'Clothing',
      amount: 197.00,
      hour: 14,
      minute: 5,
    ),
    (
      id: 'showcase-receipt-tech',
      merchant: 'PixelTech',
      category: 'Tech',
      amount: 223.00,
      hour: 11,
      minute: 20,
    ),
  ];

  return [
    for (final s in showcases)
      TransactionView(
        id: s.id,
        occurredAt: at(s.hour, s.minute),
        amountMyr: s.amount,
        needsAmount: false,
        merchantRaw: s.merchant,
        categoryGuess: s.category,
        categoryUser: null,
        placeName: s.merchant,
        placeGooglePlaceId: null,
        placeLat: 3.1390,
        placeLng: 101.6869,
        syncStatus: 'synced',
        pipelineStatus: 'provisional',
        localThumbnailPath: null,
      ),
  ];
}
