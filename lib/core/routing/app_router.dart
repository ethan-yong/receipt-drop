import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bootstrap/app_prefs.dart';
import '../config/env.dart';
import 'auth_refresh.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/friends/friends_teaser_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/spend_map_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/places/places_search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/share/share_hint_screen.dart';
import '../../features/tx_detail/transaction_detail_screen.dart';
import '../../widgets/main_shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// Builds the router with auth + onboarding redirects.
GoRouter createAppRouter(AuthRefreshNotifier refresh) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;

      if (Env.skipAuth) {
        if (path == '/auth' || path == '/onboarding') return '/home';
        return null;
      }

      final loggedIn =
          Supabase.instance.client.auth.currentSession != null;
      final onboardingDone = AppPrefs.onboardingComplete;

      if (!onboardingDone && path != '/onboarding') {
        return '/onboarding';
      }
      if (onboardingDone && !loggedIn && path == '/onboarding') {
        return '/auth';
      }
      if (onboardingDone &&
          !loggedIn &&
          path != '/auth' &&
          path != '/onboarding') {
        return '/auth';
      }
      if (loggedIn && (path == '/auth' || path == '/onboarding')) {
        return '/home';
      }
      return null;
    },
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/home',
                name: 'home',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: HomeScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/map',
                name: 'map',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: SpendMapScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/dashboard',
                name: 'dashboard',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: DashboardScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                name: 'settings',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/share-hint',
        name: 'share-hint',
        builder: (context, state) => const ShareHintScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth',
        name: 'auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/friends-teaser',
        name: 'friends-teaser',
        builder: (context, state) => const FriendsTeaserScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/tx/:id',
        name: 'tx-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return TransactionDetailScreen(transactionId: id);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/places-search',
        name: 'places-search',
        builder: (context, state) => const PlacesSearchScreen(),
      ),
    ],
  );
}
