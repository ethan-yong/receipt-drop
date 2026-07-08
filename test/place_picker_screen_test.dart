import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/core/theme/receipt_sheet_theme.dart';
import 'package:receipt_drop/data/repositories/places_repository.dart';
import 'package:receipt_drop/domain/logic/merchant_extractor.dart';
import 'package:receipt_drop/features/places/place_picker_screen.dart';
import 'package:receipt_drop/widgets/receipt_sheet_widgets.dart';

// Verified minimal 1×1 transparent PNG — avoids any network requests in tests.
final _kTransparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x62, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

/// Tile provider that returns a transparent 1×1 PNG without making HTTP
/// requests, so tests don't leave pending timers after the widget tree is
/// disposed.
class _NoNetworkTileProvider extends TileProvider {
  @override
  ImageProvider<Object> getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) =>
      MemoryImage(_kTransparentPng);
}

const _candidates = [
  PlaceCandidate(
    id: 'p1',
    name: 'Mamak Corner',
    address: '1 Jalan Test',
    lat: 3.1001,
    lng: 101.6001,
    distanceMeters: 45,
    confidence: 0.9,
  ),
  PlaceCandidate(
    id: 'p2',
    name: 'Restoran Nasi Lemak',
    address: '2 Jalan Test',
    lat: 3.1002,
    lng: 101.6002,
    distanceMeters: 120,
    confidence: 0.75,
  ),
];

NearbyFetcher _makeStub(List<PlaceCandidate> results) => ({
      required double lat,
      required double lng,
      List<MerchantCandidate> candidates = const [],
      String? merchantName,
      String? category,
      int limit = 5,
    }) async =>
        results;

Widget _buildPicker(
  NearbyFetcher fetcher, {
  PlaceSearchFetcher? searchFetcher,
}) =>
    MaterialApp(
      theme: buildReceiptDropTestTheme(),
      home: PlacePickerScreen(
        lat: 3.1234,
        lng: 101.6789,
        candidates: const [],
        candidatesFetcher: fetcher,
        searchFetcher: searchFetcher,
        tileProvider: _NoNetworkTileProvider(),
      ),
    );

/// Pump the widget, wait for the async fetch, and run the 550 ms sheet
/// entrance animation to completion so taps land on settled positions.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  await tester.pump(); // flush the async fetch + setState
  await tester.pump(); // process the post-frame camera-move callback
  await tester.pump(const Duration(milliseconds: 600)); // sheet slide-up
}

ReceiptSheetCta _cta(WidgetTester tester) =>
    tester.widget<ReceiptSheetCta>(find.byType(ReceiptSheetCta));

void main() {
  setUpAll(() {
    // No Google Fonts fetches in tests (same reason buildReceiptDropTestTheme
    // exists).
    debugReceiptSheetSystemFont = true;
  });

  testWidgets('shows loading indicator then candidate list', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));

    // Initially loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpUntilLoaded(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mamak Corner'), findsOneWidget);
    expect(find.text('Restoran Nasi Lemak'), findsOneWidget);
    expect(find.text('2 spots found nearby'), findsOneWidget);
  });

  testWidgets('Confirm is enabled after first candidate auto-selection',
      (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));
    await _pumpUntilLoaded(tester);

    expect(_cta(tester).onPressed, isNotNull);
  });

  testWidgets('tapping a row keeps Confirm enabled', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));
    await _pumpUntilLoaded(tester);

    await tester.tap(find.text('Restoran Nasi Lemak'));
    await tester.pump();
    // Advance past the 550 ms camera animation so it doesn't bleed into later pumps.
    await tester.pump(const Duration(milliseconds: 600));

    expect(_cta(tester).onPressed, isNotNull);
  });

  testWidgets('Confirm pops with the auto-selected PlaceResult', (tester) async {
    PlaceResult? returned;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<PlaceResult?>(
                MaterialPageRoute(
                  builder: (_) => PlacePickerScreen(
                    lat: 3.1234,
                    lng: 101.6789,
                    candidates: const [],
                    candidatesFetcher: _makeStub(_candidates),
                    tileProvider: _NoNetworkTileProvider(),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump(); // navigate to picker
    await tester.pump(const Duration(milliseconds: 400)); // route transition
    await _pumpUntilLoaded(tester); // fetch + sheet entrance

    await tester.tap(find.text('Confirm location'));
    await tester.pump(); // initiates pop
    await tester.pump(const Duration(milliseconds: 400)); // route transition

    expect(returned?.id, 'p1');
    expect(returned?.name, 'Mamak Corner');
    expect(returned?.lat, closeTo(3.1001, 0.0001));
  });

  testWidgets('Confirm pops with the user-selected (second) candidate',
      (tester) async {
    PlaceResult? returned;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<PlaceResult?>(
                MaterialPageRoute(
                  builder: (_) => PlacePickerScreen(
                    lat: 3.1234,
                    lng: 101.6789,
                    candidates: const [],
                    candidatesFetcher: _makeStub(_candidates),
                    tileProvider: _NoNetworkTileProvider(),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntilLoaded(tester);

    await tester.tap(find.text('Restoran Nasi Lemak'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Confirm location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned?.id, 'p2');
    expect(returned?.name, 'Restoran Nasi Lemak');
  });

  testWidgets('empty state opens in-sheet search mode', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(const [])));
    await _pumpUntilLoaded(tester);

    expect(find.text('No nearby places found'), findsOneWidget);
    expect(find.byType(ReceiptSheetCta), findsNothing);

    await tester.tap(find.text('Search by name instead'));
    await tester.pump();

    expect(find.text('Search for a restaurant or address'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('search promotes a picked result and Confirm returns it',
      (tester) async {
    PlaceResult? returned;
    const searchHit = PlaceResult(
      id: 's1',
      name: 'Mamak Corner – USJ 1',
      address: 'Persiaran Subang Permai, USJ',
      lat: 3.11,
      lng: 101.61,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              returned = await Navigator.of(context).push<PlaceResult?>(
                MaterialPageRoute(
                  builder: (_) => PlacePickerScreen(
                    lat: 3.1234,
                    lng: 101.6789,
                    candidates: const [],
                    candidatesFetcher: _makeStub(_candidates),
                    searchFetcher: (query, {lat, lng}) async => [searchHit],
                    tileProvider: _NoNetworkTileProvider(),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _pumpUntilLoaded(tester);

    // Tapping the map's search pill opens search mode.
    await tester.tap(find.text('Which restaurant was this?'));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'mamak usj');
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pump(); // fetch resolves

    expect(find.text('Mamak Corner – USJ 1'), findsOneWidget);

    await tester.tap(find.text('Mamak Corner – USJ 1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // camera animation

    // Back in browse mode with the search hit promoted and selected.
    expect(find.text('3 spots found nearby'), findsOneWidget);

    await tester.tap(find.text('Confirm location'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned?.id, 's1');
    expect(returned?.name, 'Mamak Corner – USJ 1');
  });
}
