
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/app.dart';
import 'package:puggy_bank/core/bootstrap/app_prefs.dart';
import 'package:puggy_bank/core/bootstrap/app_services.dart';
import 'package:puggy_bank/core/routing/app_router.dart';
import 'package:puggy_bank/core/routing/auth_refresh.dart';
import 'package:puggy_bank/core/theme/app_theme.dart';
import 'package:puggy_bank/data/remote/supabase_client_holder.dart';
import 'package:puggy_bank/data/repositories/ingest_receipt_request.dart';
import 'package:puggy_bank/features/share/receipt_file_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await initializeSupabase(
      url: 'http://127.0.0.1:54321',
      anonKey: 'sb_publishable_mock_for_tests_only',
    );
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '.';
        }
        return null;
      },
    );
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await AppPrefs.init();
    await AppServices.initForTest();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await AppServices.dispose();
  });

  testWidgets('Home tab loads hero scene and CTA', (
    WidgetTester tester,
  ) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(
      PuggyBankApp(routerConfig: router, theme: buildPuggyTestTheme()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Drop Receipt'), findsOneWidget);
    expect(find.text('BADGES'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('FAB opens receipt capture menu', (WidgetTester tester) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(
      PuggyBankApp(routerConfig: router, theme: buildPuggyTestTheme()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Add a receipt'), findsOneWidget);
    expect(find.text('Choose file (image or PDF)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  test('ingestReceipt increments transaction count', () async {
    final stored = await persistReceiptBytes(
      Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
      'image/png',
    );

    final before = await AppServices.transactions.countAll();
    await AppServices.transactions.ingestReceipt(
      IngestReceiptRequest(
        localFilePath: stored.localPath,
        mimeType: stored.mimeType,
        amountMyr: 42,
        needsAmount: false,
        merchantRaw: null,
        categoryGuess: 'other',
        thumbnailBytes: stored.bytes,
        impactUser: 'med',
      ),
    );
    final after = await AppServices.transactions.countAll();
    expect(after, before + 1);
  });
}
