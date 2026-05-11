import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/app.dart';
import 'package:puggy_bank/core/bootstrap/app_prefs.dart';
import 'package:puggy_bank/core/routing/app_router.dart';
import 'package:puggy_bank/core/routing/auth_refresh.dart';
import 'package:puggy_bank/data/remote/supabase_client_holder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await AppPrefs.init();
    await initializeSupabase(
      url: 'http://127.0.0.1:54321',
      anonKey: 'sb_publishable_mock_for_tests_only',
    );
  });

  testWidgets('Auth gate shows sign-in when logged out', (
    WidgetTester tester,
  ) async {
    final refresh = AuthRefreshNotifier();
    final router = createAppRouter(refresh);

    await tester.pumpWidget(PuggyBankApp(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to PuggyBank'), findsOneWidget);
  });
}
