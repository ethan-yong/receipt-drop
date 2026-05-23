import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:puggy_bank/app.dart';
import 'package:puggy_bank/core/bootstrap/app_prefs.dart';
import 'package:puggy_bank/core/bootstrap/app_services.dart';
import 'package:puggy_bank/core/routing/app_router.dart';
import 'package:puggy_bank/core/routing/auth_refresh.dart';
import 'package:puggy_bank/data/remote/supabase_client_holder.dart';
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

    // Close Drift before unmounting so stream teardown does not leave pending timers.
    await AppServices.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  });
}
