import 'package:supabase_flutter/supabase_flutter.dart';

/// Initializes the global Supabase client. Call once from [main] after reading [Env].
Future<void> initializeSupabase({
  required String url,
  required String anonKey,
}) async {
  await Supabase.initialize(
    url: url,
    anonKey: anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
}
