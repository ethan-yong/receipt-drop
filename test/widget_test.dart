import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:puggy_bank/app.dart';
import 'package:puggy_bank/core/bootstrap/app_prefs.dart';
import 'package:puggy_bank/core/bootstrap/app_services.dart';
import 'package:puggy_bank/core/routing/app_router.dart';
import 'package:puggy_bank/core/routing/auth_refresh.dart';
import 'package:puggy_bank/data/remote/supabase_client_holder.dart';
import 'package:puggy_bank/data/repositories/ingest_receipt_request.dart';
import 'package:puggy_bank/features/share/receipt_ingest_service.dart';
import 'package:puggy_bank/features/share/share_save_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await AppPrefs.init();
    await AppServices.initForTest();
    await initializeSupabase(
      url: 'http://127.0.0.1:54321',
      anonKey: 'sb_publishable_mock_for_tests_only',
    );
  });

  testWidgets('Home tab loads with transaction feed', (
    WidgetTester tester,
  ) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(PuggyBankApp(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('PuggyBank'), findsWidgets);
    expect(find.text('7-Eleven Sunway'), findsOneWidget);

    await AppServices.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('FAB opens receipt capture menu', (WidgetTester tester) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(PuggyBankApp(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Add a receipt'), findsOneWidget);
    expect(find.text('Choose file (image or PDF)'), findsOneWidget);

    await AppServices.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Saving receipt from sheet adds row on Home', (
    WidgetTester tester,
  ) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(PuggyBankApp(routerConfig: router));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    final draft = await ReceiptIngestService.ingestBytes(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'image/jpeg',
    );

    final context = tester.element(find.byType(FloatingActionButton));
    await ShareSaveSheet.show(
      context,
      draft: draft,
      onSave: (amount, savedDraft) async {
        await AppServices.transactions.ingestReceipt(
          IngestReceiptRequest(
            localFilePath: savedDraft.localFilePath,
            mimeType: savedDraft.mimeType,
            amountMyr: amount,
            needsAmount: false,
            merchantRaw: savedDraft.merchantRaw,
            categoryGuess: savedDraft.categoryGuess,
            thumbnailBytes: savedDraft.thumbnailBytes,
          ),
        );
      },
      onCancel: ReceiptIngestService.discardDraft,
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '42.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('RM 42.00'), findsOneWidget);

    await AppServices.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
