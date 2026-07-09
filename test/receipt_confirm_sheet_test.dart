import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/core/theme/receipt_sheet_theme.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';
import 'package:receipt_drop/features/share/receipt_confirm_sheet.dart';
import 'package:receipt_drop/features/share/receipt_ingest_draft.dart';

const _items = [
  ReceiptLineItem(name: 'Rsb Biasa', priceMyr: 7.00),
  ReceiptLineItem(name: 'Teh O Limau Ais', priceMyr: 8.70, quantity: 3),
  ReceiptLineItem(name: 'Milo Ais Bungkus', priceMyr: 4.20),
];

ReceiptIngestDraft _draft({
  double? amount = 19.90,
  List<ReceiptLineItem> lineItems = _items,
  String? merchantRaw = 'SF CAFE SDN BHD',
  double? shareLocationLat,
  double? shareLocationLng,
}) {
  return ReceiptIngestDraft(
    localFilePath: 'receipts/test.jpg',
    mimeType: 'image/jpeg',
    amountMyr: amount,
    needsAmount: amount == null,
    merchantRaw: merchantRaw,
    categoryGuess: 'Food & Drink',
    lineItems: lineItems,
    shareLocationLat: shareLocationLat,
    shareLocationLng: shareLocationLng,
  );
}

/// Hosts the sheet behind a launcher button so tests can observe the value
/// [ReceiptConfirmSheet.show] pops with.
Future<void> _openSheet(
  WidgetTester tester,
  ReceiptIngestDraft draft,
  void Function(ReceiptIngestDraft? result) onClosed,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildReceiptDropTestTheme(),
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onClosed(await ReceiptConfirmSheet.show(context, draft: draft));
          },
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // sheet entrance
}

void main() {
  setUpAll(() {
    // No Google Fonts fetches in tests (same reason buildReceiptDropTestTheme
    // exists).
    debugReceiptSheetSystemFont = true;
  });

  testWidgets('renders vendor, total, category and item rows', (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    expect(find.text('Sf Cafe'), findsOneWidget); // cleaned merchant
    expect(find.text('RM 19.90'), findsOneWidget);
    expect(find.text('Food & Drink'), findsOneWidget);
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa'), findsOneWidget);
    expect(find.text('3× Teh O Limau Ais'), findsOneWidget);
    expect(find.text('RM 8.70'), findsOneWidget);
    expect(find.text('Looks good'), findsOneWidget);
  });

  testWidgets('unchecking an item recalculates the total and shows Undo',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();

    expect(find.text('RM 12.90'), findsOneWidget);
    expect(find.text('2 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa excluded'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(find.text('RM 19.90'), findsOneWidget);
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa excluded'), findsNothing);
  });

  testWidgets('undo banner auto-hides after 4 seconds but keeps the exclusion',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();
    expect(find.text('Rsb Biasa excluded'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Rsb Biasa excluded'), findsNothing);
    expect(find.text('RM 12.90'), findsOneWidget);
  });

  testWidgets('Looks good pops the draft with exclusions applied',
      (tester) async {
    ReceiptIngestDraft? returned;
    var closed = false;
    await _openSheet(tester, _draft(), (result) {
      returned = result;
      closed = true;
    });

    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();

    await tester.tap(find.text('Looks good'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // sheet dismissal

    expect(closed, isTrue);
    expect(returned, isNotNull);
    expect(returned!.amountMyr, closeTo(12.90, 0.001));
    expect(returned!.needsAmount, isFalse);
    expect(returned!.lineItems.map((i) => i.name),
        ['Teh O Limau Ais', 'Milo Ais Bungkus']);
  });

  testWidgets('untouched Looks good passes the draft through unchanged',
      (tester) async {
    ReceiptIngestDraft? returned;
    await _openSheet(tester, _draft(), (result) => returned = result);

    await tester.tap(find.text('Looks good'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned!.amountMyr, closeTo(19.90, 0.001));
    expect(returned!.lineItems.length, 3);
    // Vendor was not renamed, so the raw OCR merchant is preserved.
    expect(returned!.merchantRaw, 'SF CAFE SDN BHD');
  });

  testWidgets('tapping the vendor name renames it and commits it on the draft',
      (tester) async {
    ReceiptIngestDraft? returned;
    await _openSheet(tester, _draft(), (result) => returned = result);

    await tester.tap(find.text('Sf Cafe'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Nasi Kandar Pelita');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Nasi Kandar Pelita'), findsOneWidget);

    await tester.tap(find.text('Looks good'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned!.merchantRaw, 'Nasi Kandar Pelita');
  });

  testWidgets(
      'tapping an item price edits it and recalculates the total on save',
      (tester) async {
    ReceiptIngestDraft? returned;
    await _openSheet(tester, _draft(), (result) => returned = result);

    await tester.tap(find.text('RM 7.00'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '9.50');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('RM 22.40'), findsOneWidget); // 19.90 + (9.50 - 7.00)

    await tester.tap(find.text('Looks good'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(returned!.amountMyr, closeTo(22.40, 0.001));
    expect(
      returned!.lineItems.firstWhere((i) => i.name == 'Rsb Biasa').priceMyr,
      closeTo(9.50, 0.001),
    );
  });

  testWidgets(
      'location pencil is shown even without a share location (falls back to search)',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});
    expect(find.byIcon(Icons.edit_location_outlined), findsOneWidget);
  });

  testWidgets('location pencil is shown when a share location is present',
      (tester) async {
    await _openSheet(
      tester,
      _draft(shareLocationLat: 3.14, shareLocationLng: 101.6),
      (_) {},
    );
    expect(find.byIcon(Icons.edit_location_outlined), findsOneWidget);
  });

  testWidgets('Cancel pops null', (tester) async {
    ReceiptIngestDraft? returned = _draft(); // sentinel, overwritten on close
    var closed = false;
    await _openSheet(tester, _draft(), (result) {
      returned = result;
      closed = true;
    });

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(returned, isNull);
  });

  testWidgets('needs-amount draft shows Edit details CTA and dash total',
      (tester) async {
    await _openSheet(tester, _draft(amount: null, lineItems: const []), (_) {});

    expect(find.text('–'), findsOneWidget);
    expect(find.text('Edit details'), findsOneWidget); // CTA takes its place
    expect(find.text('Looks good'), findsNothing);
    expect(
      find.text("We couldn't read the amount — you can enter it next."),
      findsOneWidget,
    );
  });
}
