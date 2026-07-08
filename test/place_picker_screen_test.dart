import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/data/repositories/places_repository.dart';
import 'package:receipt_drop/domain/logic/merchant_extractor.dart';
import 'package:receipt_drop/features/places/place_picker_screen.dart';

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

Widget _buildPicker(NearbyFetcher fetcher) => MaterialApp(
      theme: buildReceiptDropTestTheme(),
      home: PlacePickerScreen(
        lat: 3.1234,
        lng: 101.6789,
        candidates: const [],
        candidatesFetcher: fetcher,
        tileProvider: _NoNetworkTileProvider(),
      ),
    );

/// Pump the widget and wait for the async fetch to complete.
/// Returns immediately after the list (or empty state) is visible.
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  await tester.pump(); // flush the async fetch + setState
  await tester.pump(); // process the post-frame camera-move callback
}

void main() {
  testWidgets('shows loading indicator then candidate list', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));

    // Initially loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pumpUntilLoaded(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Mamak Corner'), findsOneWidget);
    expect(find.text('Restoran Nasi Lemak'), findsOneWidget);
  });

  testWidgets('Confirm button is enabled after first candidate auto-selection',
      (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));
    await _pumpUntilLoaded(tester);

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('tapping a row keeps Confirm enabled', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(_candidates)));
    await _pumpUntilLoaded(tester);

    await tester.tap(find.text('Restoran Nasi Lemak'));
    await tester.pump();
    // Advance past the 550 ms camera animation so it doesn't bleed into later pumps.
    await tester.pump(const Duration(milliseconds: 600));

    final btn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirm'),
    );
    expect(btn.onPressed, isNotNull);
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
    await _pumpUntilLoaded(tester); // fetch + settle

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
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
    await _pumpUntilLoaded(tester);

    await tester.tap(find.text('Restoran Nasi Lemak'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned?.id, 'p2');
    expect(returned?.name, 'Restoran Nasi Lemak');
  });

  testWidgets('shows empty state when no candidates returned', (tester) async {
    await tester.pumpWidget(_buildPicker(_makeStub(const [])));
    await _pumpUntilLoaded(tester);

    expect(find.text('No nearby places found'), findsOneWidget);
    expect(find.text('Search by name instead'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Confirm'), findsNothing);
  });

  testWidgets('Search by name instead pops null', (tester) async {
    PlaceResult? returned;
    bool popped = false;

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
                    candidatesFetcher: _makeStub(const []),
                    tileProvider: _NoNetworkTileProvider(),
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await _pumpUntilLoaded(tester);

    await tester.tap(find.text('Search by name instead'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(popped, isTrue);
    expect(returned, isNull);
  });
}
