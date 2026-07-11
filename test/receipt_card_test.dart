import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/models/transaction_view.dart';
import 'package:receipt_drop/widgets/receipt_card.dart';

TransactionView _tx({
  required String categoryGuess,
  Uint8List? thumbnailBytes,
}) {
  return TransactionView(
    id: 'tx-1',
    occurredAt: DateTime(2026, 7, 10),
    amountMyr: 21.70,
    needsAmount: false,
    merchantRaw: 'Restoran Anwar Maju',
    categoryGuess: categoryGuess,
    categoryUser: null,
    placeName: null,
    placeGooglePlaceId: null,
    placeLat: null,
    placeLng: null,
    syncStatus: 'synced',
    pipelineStatus: 'enriched',
    localThumbnailPath: null,
    thumbnailBytes: thumbnailBytes,
  );
}

void main() {
  group('receiptIllustrationAssetForCategory', () {
    test('Travel resolves to the bundled travel asset', () {
      expect(
        receiptIllustrationAssetForCategory('Travel'),
        'category_images/travel.png',
      );
    });

    test('Health & Beauty resolves to the bundled asset', () {
      expect(
        receiptIllustrationAssetForCategory('Health & Beauty'),
        'category_images/health_and_beauty.png',
      );
    });

    test('Transport resolves to the bundled transport asset', () {
      expect(
        receiptIllustrationAssetForCategory('Transport'),
        'category_images/transport.png',
      );
    });

    test('Others has no bundled asset', () {
      expect(receiptIllustrationAssetForCategory('Others'), isNull);
    });
  });

  group('ReceiptCard illustration', () {
    testWidgets(
        'never shows the captured photo, even when thumbnailBytes is set',
        (tester) async {
      // A 1x1 transparent PNG — just needs to be non-empty/decodable bytes.
      final fakePhoto = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptCard(
              tx: _tx(categoryGuess: 'Transport', thumbnailBytes: fakePhoto),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage),
          findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'category_images/transport.png',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders the bundled asset for a category that has one',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReceiptCard(tx: _tx(categoryGuess: 'Health & Beauty')),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'category_images/health_and_beauty.png',
        ),
        findsOneWidget,
      );
    });
  });
}
