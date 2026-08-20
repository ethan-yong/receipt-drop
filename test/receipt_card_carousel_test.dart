import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';
import 'package:receipt_drop/widgets/receipt_card.dart';
import 'package:receipt_drop/widgets/receipt_card_carousel.dart';
import 'package:receipt_drop/widgets/receipt_carousel_physics.dart';

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

/// Finds the currently-centered card slot, keyed by the carousel itself.
Finder _activeCard(int index) =>
    find.byKey(ValueKey('receipt-carousel-active-$index'));

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

Future<void> _settle(WidgetTester tester) async {
  // Friction glide + spring settle can take up to ~2s for a hard flick;
  // pump past it without binding to infinite auto-rotate timers.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('shows an empty receipt placeholder when there are no receipts', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const ReceiptCardCarousel(transactions: [])),
    );
    await tester.pump();

    expect(find.text(EmptyReceiptCard.invitationCopy), findsOneWidget);
    expect(find.text('No receipts today yet'), findsNothing);

    final placeholder = find.byType(EmptyReceiptCard);
    expect(placeholder, findsOneWidget);
    final size = tester.getSize(placeholder);
    expect(size.height, kReceiptCardHeight);
    // Default test viewport is 800 wide; card is kCardWidthFraction of that.
    expect(size.width, closeTo(800 * kCardWidthFraction, 0.5));
  });

  testWidgets('tapping the empty placeholder fires onEmptyTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _harness(
        ReceiptCardCarousel(
          transactions: const [],
          onEmptyTap: () => tapped = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text(EmptyReceiptCard.invitationCopy));
    await tester.pump();

    expect(tapped, isTrue);
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

  testWidgets(
    'multiple receipts show one dot per receipt and mark the centered card active',
    (tester) async {
      final txs = _threeReceipts();

      await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: txs)));
      await tester.pump();

      expect(find.byKey(const ValueKey('receipt-carousel-dots')), findsOneWidget);
      // Starts centered on the newest receipt (index 0).
      expect(_activeCard(0), findsOneWidget);
      expect(find.textContaining('Latest Spending'), findsOneWidget);
    },
  );

  testWidgets('neighbor receipts peek in at rest, not just the active card', (
    tester,
  ) async {
    final txs = _fiveReceipts();

    await tester.pumpWidget(_harness(ReceiptCardCarousel(transactions: txs)));
    await tester.pump();

    expect(_activeCard(0), findsOneWidget);
    // Immediate neighbors are legitimately visible (peeking), unlike the old
    // single-card-at-rest model.
    expect(find.text('Receipt 1'), findsWidgets);
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
    await _settle(tester);

    expect(_activeCard(2), findsOneWidget);
    // Only the newest receipt (index 0) ever gets the badge, regardless of
    // which card is currently centered.
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
    await _settle(tester);
    expect(_activeCard(1), findsOneWidget);

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

    expect(_activeCard(0), findsOneWidget);
    expect(find.textContaining('Latest Spending'), findsOneWidget);
  });

  testWidgets('slow left swipe advances exactly one receipt', (tester) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _threeReceipts())),
    );
    await tester.pump();

    await tester.fling(
      find.text('Newest Spot').first,
      const Offset(-500, 0),
      600,
    );
    await _settle(tester);

    expect(_activeCard(1), findsOneWidget);
  });

  testWidgets('fast left fling can skip past the next receipt', (tester) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _fiveReceipts())),
    );
    await tester.pump();

    await tester.fling(
      find.text('Receipt 0').first,
      const Offset(-300, 0),
      4000,
    );
    await _settle(tester);

    // Should have advanced at least two pages (not stuck on 0 or 1).
    expect(_activeCard(0), findsNothing);
    expect(_activeCard(1), findsNothing);
  });

  testWidgets('hard flick decelerates and settles centered on one receipt', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _fiveReceipts())),
    );
    await tester.pump();

    await tester.fling(
      find.text('Receipt 0').first,
      const Offset(-300, 0),
      4000,
    );
    await _settle(tester);

    // Exactly one card is centered after settling.
    final activeKeys = List.generate(5, _activeCard);
    final activeCount = activeKeys.where((f) => f.evaluate().isNotEmpty).length;
    expect(activeCount, 1);
  });

  testWidgets('tapping a peeking neighbor recenters it instead of opening detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ReceiptCardCarousel(transactions: _fiveReceipts())),
    );
    await tester.pump();

    expect(_activeCard(0), findsOneWidget);

    // A peeking neighbor only shows a sliver of its edge (its own text may
    // be off-screen), so tap just past the active card's visible edge
    // rather than by finding the neighbor's text.
    final activeRect = tester.getRect(_activeCard(0));
    // The neighbor is both translated out and scaled down around its own
    // (pre-translation) center, so its visible sliver starts noticeably
    // further right than the active card's raw edge — tap well inside it.
    await tester.tapAt(Offset(activeRect.right + 55, activeRect.center.dy));
    await _settle(tester);

    expect(_activeCard(1), findsOneWidget);
    // Recentering, not navigation — the detail route was never pushed.
    expect(find.textContaining('detail-'), findsNothing);
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
      const Offset(-40, 0),
      80,
    );
    await _settle(tester);

    expect(_activeCard(0), findsOneWidget);
  });
}
