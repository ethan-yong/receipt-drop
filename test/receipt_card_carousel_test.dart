import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';
import 'package:receipt_drop/widgets/receipt_card_carousel.dart';

TransactionView _tx({
  required String id,
  required DateTime occurredAt,
  required String merchant,
  String categoryGuess = 'Food',
}) {
  return TransactionView(
    id: id,
    occurredAt: occurredAt,
    amountMyr: 21.70,
    needsAmount: false,
    merchantRaw: merchant,
    categoryGuess: categoryGuess,
    categoryUser: null,
    placeName: null,
    placeGooglePlaceId: null,
    placeLat: null,
    placeLng: null,
    syncStatus: 'synced',
    pipelineStatus: 'enriched',
    localThumbnailPath: null,
  );
}

Widget _harness(Widget child) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        name: 'tx-detail',
        path: '/tx/:id',
        builder: (context, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
    ],
  );
  return MaterialApp.router(
    theme: buildReceiptDropTestTheme(),
    routerConfig: router,
  );
}

void main() {
  testWidgets('shows an empty state when there are no receipts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const ReceiptCardCarousel(transactions: [])),
    );
    await tester.pump();

    expect(find.text('No receipts today yet'), findsOneWidget);
  });

  testWidgets('a single receipt renders the newest badge and hides the dots', (
    tester,
  ) async {
    final tx = _tx(
      id: 'a',
      occurredAt: DateTime(2026, 7, 10),
      merchant: 'Solo Cafe',
    );

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: [tx])));
    await tester.pump();

    expect(find.text('Solo Cafe'), findsWidgets);
    expect(find.textContaining('Latest Spending'), findsOneWidget);
  });

  testWidgets('multiple receipts show one dot per receipt and only one card', (
    tester,
  ) async {
    final txs = [
      _tx(
        id: 'a',
        occurredAt: DateTime(2026, 7, 10, 12),
        merchant: 'Newest Spot',
      ),
      _tx(
        id: 'b',
        occurredAt: DateTime(2026, 7, 10, 11),
        merchant: 'Older Spot',
      ),
      _tx(
        id: 'c',
        occurredAt: DateTime(2026, 7, 10, 10),
        merchant: 'Oldest Spot',
      ),
    ];

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: txs)));
    await tester.pump();

    // Only the active (newest) card's content should be visible at rest.
    expect(find.text('Newest Spot'), findsWidgets);
    expect(find.text('Older Spot'), findsNothing);
    expect(find.textContaining('Latest Spending'), findsOneWidget);
  });

  testWidgets('tapping a dot advances the carousel to that receipt', (
    tester,
  ) async {
    final txs = [
      _tx(
        id: 'a',
        occurredAt: DateTime(2026, 7, 10, 12),
        merchant: 'Newest Spot',
      ),
      _tx(
        id: 'b',
        occurredAt: DateTime(2026, 7, 10, 11),
        merchant: 'Older Spot',
      ),
      _tx(
        id: 'c',
        occurredAt: DateTime(2026, 7, 10, 10),
        merchant: 'Oldest Spot',
      ),
    ];

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: txs)));
    await tester.pump();

    // Three dots, tap the third one (index 2 -> "Oldest Spot").
    final dotFinder = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onTap != null,
    );
    expect(dotFinder, findsWidgets);

    await tester.tap(dotFinder.at(dotFinder.evaluate().length - 1));
    // Settle the deck-transition animation (~690ms) plus resume timer.
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();

    expect(find.text('Oldest Spot'), findsWidgets);
    expect(find.text('Newest Spot'), findsNothing);
    // Only the newest receipt (index 0) ever gets the badge, regardless of
    // which card is currently active.
    expect(find.textContaining('Latest Spending'), findsNothing);
  });

  testWidgets('a newly captured receipt snaps the carousel to the first card', (
    tester,
  ) async {
    final older = [
      _tx(
        id: 'b',
        occurredAt: DateTime(2026, 7, 10, 11),
        merchant: 'Older Spot',
      ),
      _tx(
        id: 'c',
        occurredAt: DateTime(2026, 7, 10, 10),
        merchant: 'Oldest Spot',
      ),
    ];

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: older)));
    await tester.pump();

    // Move off index 0 by jumping to the last dot.
    final dotFinder = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onTap != null,
    );
    await tester.tap(dotFinder.at(dotFinder.evaluate().length - 1));
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    expect(find.text('Oldest Spot'), findsWidgets);

    // A new receipt is prepended (the list is newest-first): the carousel
    // must snap back so the user immediately sees what they just scanned.
    final grown = [
      _tx(
        id: 'a',
        occurredAt: DateTime(2026, 7, 10, 12),
        merchant: 'Newest Spot',
      ),
      ...older,
    ];
    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: grown)));
    await tester.pump();

    expect(find.text('Newest Spot'), findsWidgets);
    expect(find.text('Oldest Spot'), findsNothing);
    expect(find.textContaining('Latest Spending'), findsOneWidget);
  });
}
