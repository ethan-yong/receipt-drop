import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/core/theme/receipt_sheet_theme.dart';
import 'package:receipt_drop/domain/logic/category_matcher.dart';
import 'package:receipt_drop/domain/logic/impact_level.dart';
import 'package:receipt_drop/domain/models/field_correction.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';
import 'package:receipt_drop/features/share/receipt_confirm_sheet.dart';
import 'package:receipt_drop/features/share/receipt_ingest_draft.dart';

final _testCategories = CategoryConfig.fromJson({
  'version': 'test',
  'default_category': 'Others',
  'rules': [
    {
      'category': 'Food & Drink',
      'any_of': ['cafe', 'restoran'],
    },
  ],
});

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
  bool lowConfidence = false,
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
    lowConfidence: lowConfidence,
  );
}

/// Hosts the sheet behind a launcher button so tests can observe the value
/// [ReceiptConfirmSheet.show] pops with, plus whatever [onSave]/[onCancel]/
/// [onSaveForLater] were invoked with (the sheet now saves directly instead
/// of just popping an edited draft).
Future<void> _openSheet(
  WidgetTester tester,
  ReceiptIngestDraft draft,
  void Function(bool result) onClosed, {
  Future<void> Function(double? amount, ReceiptIngestDraft draft, ImpactLevel impact)?
      onSave,
  Future<void> Function(ReceiptIngestDraft draft)? onCancel,
  Future<void> Function(ReceiptIngestDraft draft)? onSaveForLater,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildReceiptDropTestTheme(),
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            onClosed(await ReceiptConfirmSheet.show(
              context,
              draft: draft,
              categories: _testCategories,
              onSave: onSave ?? (_, _, _) async {},
              onCancel: onCancel ?? (_) async {},
              onSaveForLater: onSaveForLater,
              mapOverride: const SizedBox.shrink(),
            ));
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

/// The total field is now always a live editable [TextField] (not a plain
/// `Text`), so its value has to be read off the controller rather than
/// matched via `find.text('RM ...')`.
String _amountFieldText(WidgetTester tester) {
  return tester
      .widget<TextField>(find.byKey(const Key('receipt-amount-field')))
      .controller!
      .text;
}

void main() {
  setUpAll(() {
    // No Google Fonts fetches in tests (same reason buildReceiptDropTestTheme
    // exists).
    debugReceiptSheetSystemFont = true;
  });

  testWidgets(
      'renders vendor, total, category, impact and item rows',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    expect(find.text('Sf Cafe'), findsOneWidget); // cleaned merchant
    expect(_amountFieldText(tester), '19.90');
    expect(find.text('Food & Drink'), findsWidgets); // chip + dropdown
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa'), findsOneWidget);
    expect(find.text('Teh O Limau Ais'), findsOneWidget);
    expect(find.text('RM 8.70'), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    expect(find.text('×1'), findsNWidgets(2));
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Impact'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Med'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('shows caution banner when confidence is low', (tester) async {
    await _openSheet(tester, _draft(lowConfidence: true), (_) {});
    expect(
      find.text("Double-check this amount — we're not fully sure."),
      findsOneWidget,
    );
  });

  testWidgets('hides caution banner when confidence is not low', (tester) async {
    await _openSheet(tester, _draft(), (_) {});
    expect(
      find.text("Double-check this amount — we're not fully sure."),
      findsNothing,
    );
  });

  testWidgets('unchecking an item recalculates the total and shows Undo',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    // The added Category dropdown + Impact picker push item rows below the
    // fold in the test viewport — scroll them into view before tapping.
    await tester.ensureVisible(find.text('Rsb Biasa'));
    await tester.pump();
    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();

    expect(_amountFieldText(tester), '12.90');
    expect(find.text('2 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa excluded'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump();

    expect(_amountFieldText(tester), '19.90');
    expect(find.text('3 of 3 items'), findsOneWidget);
    expect(find.text('Rsb Biasa excluded'), findsNothing);
  });

  testWidgets('undo banner auto-hides after 4 seconds but keeps the exclusion',
      (tester) async {
    await _openSheet(tester, _draft(), (_) {});

    // The added Category dropdown + Impact picker push item rows below the
    // fold in the test viewport — scroll them into view before tapping.
    await tester.ensureVisible(find.text('Rsb Biasa'));
    await tester.pump();
    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();
    expect(find.text('Rsb Biasa excluded'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Rsb Biasa excluded'), findsNothing);
    expect(_amountFieldText(tester), '12.90');
  });

  testWidgets('Save invokes onSave with exclusions applied and pops true',
      (tester) async {
    double? savedAmount;
    ReceiptIngestDraft? savedDraft;
    bool? result;
    var closed = false;
    await _openSheet(
      tester,
      _draft(),
      (r) {
        result = r;
        closed = true;
      },
      onSave: (amount, draft, impact) async {
        savedAmount = amount;
        savedDraft = draft;
      },
    );

    // The added Category dropdown + Impact picker push item rows below the
    // fold in the test viewport — scroll them into view before tapping.
    await tester.ensureVisible(find.text('Rsb Biasa'));
    await tester.pump();
    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(result, isTrue);
    expect(savedAmount, closeTo(12.90, 0.001));
    expect(savedDraft!.lineItems.map((i) => i.name),
        ['Teh O Limau Ais', 'Milo Ais Bungkus']);
  });

  testWidgets('untouched Save passes amount and draft through unchanged',
      (tester) async {
    double? savedAmount;
    ReceiptIngestDraft? savedDraft;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async {
        savedAmount = amount;
        savedDraft = draft;
      },
    );

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedAmount, closeTo(19.90, 0.001));
    expect(savedDraft!.lineItems.length, 3);
    // Vendor was not renamed, so the raw OCR merchant is preserved.
    expect(savedDraft!.merchantRaw, 'SF CAFE SDN BHD');
  });

  testWidgets('tapping the vendor name renames it and commits it on the draft',
      (tester) async {
    ReceiptIngestDraft? savedDraft;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async => savedDraft = draft,
    );

    await tester.tap(find.text('Sf Cafe'));
    await tester.pump();

    final vendorField = find.byKey(const Key('receipt-vendor-field'));
    expect(vendorField, findsOneWidget);
    await tester.enterText(vendorField, 'Nasi Kandar Pelita');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(vendorField, findsNothing);
    expect(find.text('Nasi Kandar Pelita'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedDraft!.merchantRaw, 'Nasi Kandar Pelita');
  });

  testWidgets(
      'tapping an item price edits it and recalculates the total on save',
      (tester) async {
    double? savedAmount;
    ReceiptIngestDraft? savedDraft;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async {
        savedAmount = amount;
        savedDraft = draft;
      },
    );

    await tester.ensureVisible(find.text('RM 7.00'));
    await tester.pump();
    await tester.tap(find.text('RM 7.00'));
    await tester.pump();

    final priceField = find.byKey(const Key('receipt-price-field'));
    expect(priceField, findsOneWidget);
    await tester.enterText(priceField, '9.50');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(priceField, findsNothing);
    expect(_amountFieldText(tester), '22.40'); // 19.90 + (9.50 - 7.00)

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedAmount, closeTo(22.40, 0.001));
    expect(
      savedDraft!.lineItems.firstWhere((i) => i.name == 'Rsb Biasa').priceMyr,
      closeTo(9.50, 0.001),
    );
  });

  group('field-correction capture', () {
    testWidgets('untouched save captures no field corrections', (tester) async {
      ReceiptIngestDraft? savedDraft;
      await _openSheet(
        tester,
        _draft(),
        (_) {},
        onSave: (amount, draft, impact) async => savedDraft = draft,
      );

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(savedDraft!.fieldCorrections, isEmpty);
    });

    testWidgets(
        'renaming the vendor captures a free-text merchant correction',
        (tester) async {
      ReceiptIngestDraft? savedDraft;
      await _openSheet(
        tester,
        _draft(),
        (_) {},
        onSave: (amount, draft, impact) async => savedDraft = draft,
      );

      await tester.tap(find.text('Sf Cafe'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('receipt-vendor-field')),
        'Nasi Kandar Pelita',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(savedDraft!.fieldCorrections, hasLength(1));
      final correction = savedDraft!.fieldCorrections.single;
      expect(correction.field, FieldCorrection.fieldMerchant);
      expect(correction.predictedValue, 'SF CAFE SDN BHD');
      expect(correction.confirmedValue, 'Nasi Kandar Pelita');
      expect(
        correction.correctionType,
        FieldCorrection.correctionTypeFreeText,
      );
    });

    testWidgets('changing the category captures a category correction',
        (tester) async {
      ReceiptIngestDraft? savedDraft;
      await _openSheet(
        tester,
        _draft(),
        (_) {},
        onSave: (amount, draft, impact) async => savedDraft = draft,
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Others').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final categoryCorrections = savedDraft!.fieldCorrections
          .where((c) => c.field == FieldCorrection.fieldCategory);
      expect(categoryCorrections, hasLength(1));
      expect(categoryCorrections.single.predictedValue, 'Food & Drink');
      expect(categoryCorrections.single.confirmedValue, 'Others');
    });

    testWidgets(
        'editing an item price captures a line-item-price correction with its index',
        (tester) async {
      ReceiptIngestDraft? savedDraft;
      await _openSheet(
        tester,
        _draft(),
        (_) {},
        onSave: (amount, draft, impact) async => savedDraft = draft,
      );

      await tester.ensureVisible(find.text('RM 7.00'));
      await tester.pump();
      await tester.tap(find.text('RM 7.00'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('receipt-price-field')),
        '9.50',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final priceCorrections = savedDraft!.fieldCorrections
          .where((c) => c.field == FieldCorrection.fieldLineItemPrice);
      expect(priceCorrections, hasLength(1));
      expect(priceCorrections.single.predictedValue, '7.00');
      expect(priceCorrections.single.confirmedValue, '9.50');
      expect(priceCorrections.single.lineItemIndex, 0);
    });
  });

  testWidgets('tapping an Impact chip overrides the derived impact on save',
      (tester) async {
    ImpactLevel? savedImpact;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async => savedImpact = impact,
    );

    await tester.ensureVisible(find.text('High'));
    await tester.tap(find.text('High'));
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedImpact, ImpactLevel.high);
  });

  testWidgets('changing the category dropdown carries through to onSave',
      (tester) async {
    ReceiptIngestDraft? savedDraft;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async => savedDraft = draft,
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedDraft!.categoryUser, 'Others');
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

  testWidgets('Cancel invokes onCancel and pops false', (tester) async {
    ReceiptIngestDraft? cancelled;
    bool? result;
    var closed = false;
    await _openSheet(
      tester,
      _draft(),
      (r) {
        result = r;
        closed = true;
      },
      onCancel: (draft) async => cancelled = draft,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(closed, isTrue);
    expect(result, isFalse);
    expect(cancelled, isNotNull);
  });

  testWidgets(
      'needs-amount draft with no line items shows an empty, editable amount field',
      (tester) async {
    await _openSheet(tester, _draft(amount: null, lineItems: const []), (_) {});

    expect(find.text('–'), findsNothing);
    expect(find.byKey(const Key('receipt-amount-field')), findsOneWidget);
    expect(_amountFieldText(tester), '');
    expect(find.text('Save'), findsOneWidget);
    expect(
      find.text("We couldn't read the amount — enter it above."),
      findsOneWidget,
    );
    expect(
      find.text("Double-check this amount — we're not fully sure."),
      findsNothing,
    );
  });

  testWidgets('needs-amount draft: typing an amount and saving invokes onSave',
      (tester) async {
    double? savedAmount;
    await _openSheet(
      tester,
      _draft(amount: null, lineItems: const []),
      (_) {},
      onSave: (amount, draft, impact) async => savedAmount = amount,
    );

    await tester.enterText(
      find.byKey(const Key('receipt-amount-field')),
      '25.00',
    );
    await tester.pump();

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedAmount, closeTo(25.00, 0.001));
  });

  testWidgets(
      'needs-amount draft with line items pre-fills the total from their sum',
      (tester) async {
    double? savedAmount;
    await _openSheet(
      tester,
      _draft(amount: null), // default _items sum to 7.00 + 8.70 + 4.20 = 19.90
      (_) {},
      onSave: (amount, draft, impact) async => savedAmount = amount,
    );

    expect(_amountFieldText(tester), '19.90');

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedAmount, closeTo(19.90, 0.001));
  });

  testWidgets(
      'the total field stays editable on a confident draft and overrides item math',
      (tester) async {
    double? savedAmount;
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSave: (amount, draft, impact) async => savedAmount = amount,
    );

    expect(_amountFieldText(tester), '19.90');

    await tester.enterText(
      find.byKey(const Key('receipt-amount-field')),
      '50.00',
    );
    await tester.pump();

    // Excluding an item afterwards must not silently overwrite what the
    // user just typed directly into the total.
    await tester.ensureVisible(find.text('Rsb Biasa'));
    await tester.pump();
    await tester.tap(find.text('Rsb Biasa'));
    await tester.pump();

    expect(_amountFieldText(tester), '50.00');

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(savedAmount, closeTo(50.00, 0.001));
  });

  testWidgets('offers Save for later on a needs-amount draft and invokes it',
      (tester) async {
    ReceiptIngestDraft? parked;
    await _openSheet(
      tester,
      _draft(amount: null, lineItems: const []),
      (_) {},
      onSaveForLater: (draft) async => parked = draft,
    );

    final button = find.text('Save for later');
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(parked, isNotNull);
    expect(parked!.needsAmount, isTrue);
  });

  testWidgets('hides Save for later on a confident draft', (tester) async {
    await _openSheet(
      tester,
      _draft(),
      (_) {},
      onSaveForLater: (_) async {},
    );

    expect(find.text('Save for later'), findsNothing);
  });

  testWidgets('hides Save for later when no callback is wired', (tester) async {
    await _openSheet(tester, _draft(amount: null, lineItems: const []), (_) {});

    expect(find.text('Save for later'), findsNothing);
  });

  group('items scroll section', () {
    List<ReceiptLineItem> manyItems(int n) => [
          for (var i = 0; i < n; i++)
            ReceiptLineItem(name: 'Line Item $i', priceMyr: 1.0 + i),
        ];

    // The default 800x600 test surface is landscape and clips the sheet.
    // Portrait, oversized to absorb the Ahem test font being wider/taller
    // than the real one, so the whole sheet body fits like on device.
    Future<void> usePhoneViewport(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets(
        'many items scroll internally while header and Save stay visible',
        (tester) async {
      await usePhoneViewport(tester);
      await _openSheet(tester, _draft(lineItems: manyItems(15)), (_) {});

      expect(tester.takeException(), isNull);

      // Header and pinned actions visible without any scrolling.
      expect(find.text('Sf Cafe'), findsOneWidget);
      expect(find.text('Impact'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(RawScrollbar), findsOneWidget);

      // Tail items only appear after scrolling the internal list.
      expect(find.text('Line Item 14'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('Line Item 14'), findsOneWidget);

      // Header did not scroll away with the items.
      expect(find.text('Sf Cafe'), findsOneWidget);
      expect(find.text('Impact'), findsOneWidget);
    });

    testWidgets('toggling and price-editing work on rows inside the scroller',
        (tester) async {
      await usePhoneViewport(tester);
      await _openSheet(tester, _draft(lineItems: manyItems(15)), (_) {});

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();

      await tester.tap(find.text('Line Item 14'));
      await tester.pump();
      expect(find.text('14 of 15 items'), findsOneWidget);
      expect(find.text('Line Item 14 excluded'), findsOneWidget);

      await tester.tap(find.text('RM 14.00')); // Line Item 13's price
      await tester.pump();
      final priceField = find.byKey(const Key('receipt-price-field'));
      expect(priceField, findsOneWidget);
      await tester.enterText(priceField, '20.00');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('RM 20.00'), findsOneWidget);
    });

    testWidgets('a short list takes only its natural height and hides the '
        'scrollbar thumb', (tester) async {
      await _openSheet(tester, _draft(), (_) {}); // 3 items

      final scrollbar =
          tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      expect(scrollbar.thumbVisibility, isFalse);

      // All items visible with no internal scrolling.
      expect(find.text('Rsb Biasa'), findsOneWidget);
      expect(find.text('Milo Ais Bungkus'), findsOneWidget);
    });
  });
}
