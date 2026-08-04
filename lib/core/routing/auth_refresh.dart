import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Notifies [GoRouter] when auth session changes (sign-in / sign-out / refresh).
class AuthRefreshNotifier extends ChangeNotifier {
  AuthRefreshNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  /// Re-runs the router's `redirect` from outside a listener callback — used
  /// after an async local-state change (e.g. AppPrefs) that the redirect
  /// reads synchronously but that doesn't itself fire onAuthStateChange.
  void refresh() => notifyListeners();
}
