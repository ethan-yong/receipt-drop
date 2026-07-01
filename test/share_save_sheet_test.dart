import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/core/theme/app_theme.dart';
import 'package:puggy_bank/features/share/receipt_ingest_draft.dart';
import 'package:puggy_bank/features/share/share_save_sheet.dart';

void main() {
  ReceiptIngestDraft draftWith({
    required double? ocrConfidence,
    bool needsAmount = false,
  }) {
    return ReceiptIngestDraft(
      localFilePath: 'receipts/test.jpg',
      mimeType: 'image/jpeg',
      amountMyr: needsAmount ? null : 12.50,
      needsAmount: needsAmount,
      merchantRaw: 'Test Merchant',
      categoryGuess: 'Others',
      ocrConfidence: ocrConfidence,
    );
  }

  Future<void> pumpSheet(WidgetTester tester, ReceiptIngestDraft draft) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPuggyTestTheme(),
        home: Scaffold(
          body: ShareSaveSheet(
            draft: draft,
            onSave: (_, _, _) async {},
            onCancel: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  const warningText =
      "Double-check this amount — we're not fully sure we read it correctly.";

  testWidgets('shows caution banner and pre-selects amount when confidence is low', (
    tester,
  ) async {
    await pumpSheet(tester, draftWith(ocrConfidence: 0.3));

    expect(find.text(warningText), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.selection.baseOffset, 0);
    expect(
      field.controller!.selection.extentOffset,
      field.controller!.text.length,
    );
  });

  testWidgets('hides caution banner when confidence is high', (tester) async {
    await pumpSheet(tester, draftWith(ocrConfidence: 0.9));

    expect(find.text(warningText), findsNothing);
  });

  testWidgets('hides caution banner when amount needs manual entry', (
    tester,
  ) async {
    await pumpSheet(
      tester,
      draftWith(ocrConfidence: 0.1, needsAmount: true),
    );

    expect(find.text(warningText), findsNothing);
  });
}
