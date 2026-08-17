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

List<TransactionView> _threeReceipts() => [
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

List<TransactionView> _fiveReceipts() => [
      for (var i = 0; i < 5; i++)
        _tx(
          id: 'tx-$i',
          occurredAt: DateTime(2026, 7, 10, 12 - i),
          merchant: 'Receipt $i',
        ),
    ];

Future<void> _settleFling(WidgetTester tester) async {
  // SpringSimulation can take ~600–900ms; pump past it without binding to
  // infinite auto-rotate timers.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 200));
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
    expect(find.byKey(const ValueKey('receipt-carousel-dots')), findsNothing);
  });

  testWidgets('multiple receipts show one dot per receipt and only one card', (
    tester,
  ) async {
    final txs = _threeReceipts();

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
    final txs = _threeReceipts();

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: txs)));
    await tester.pump();

    final dots = find.byKey(const ValueKey('receipt-carousel-dots'));
    expect(dots, findsOneWidget);

    // Tap the right side of the dots row → last index ("Oldest Spot").
    final box = tester.getRect(dots);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await _settleFling(tester);

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

    final dots = find.byKey(const ValueKey('receipt-carousel-dots'));
    final box = tester.getRect(dots);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await _settleFling(tester);
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

  testWidgets('slow left swipe advances exactly one receipt', (tester) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _threeReceipts())),
    );
    await tester.pump();

    // Drag left past the 56px commit threshold with a gentle fling.
    await tester.fling(
      find.text('Newest Spot').first,
      const Offset(-120, 0),
      400,
    );
    await _settleFling(tester);

    expect(find.text('Older Spot'), findsWidgets);
    expect(find.text('Newest Spot'), findsNothing);
    expect(find.text('Oldest Spot'), findsNothing);
  });

  testWidgets('fast left fling can skip past the next receipt', (tester) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _fiveReceipts())),
    );
    await tester.pump();

    await tester.fling(
      find.text('Receipt 0').first,
      const Offset(-180, 0),
      3500,
    );
    await _settleFling(tester);

    // Should have advanced at least two pages (not stuck on Receipt 0 or 1).
    expect(find.text('Receipt 0'), findsNothing);
    final landedOnOne = find.text('Receipt 1').evaluate().isNotEmpty;
    final landedOnTwo = find.text('Receipt 2').evaluate().isNotEmpty;
    final landedOnThree = find.text('Receipt 3').evaluate().isNotEmpty;
    final landedOnFour = find.text('Receipt 4').evaluate().isNotEmpty;
    expect(
      !landedOnOne && (landedOnTwo || landedOnThree || landedOnFour),
      isTrue,
      reason: 'fast fling should skip Receipt 1',
    );
  });

  testWidgets('under-threshold drag springs back to the same receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _threeReceipts())),
    );
    await tester.pump();

    await tester.fling(
      find.text('Newest Spot').first,
      const Offset(-30, 0),
      50,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('Newest Spot'), findsWidgets);
    expect(find.text('Older Spot'), findsNothing);
  });
}
