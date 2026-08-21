import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bootstrap/app_prefs.dart';
import '../config/env.dart';
import 'auth_refresh.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/avatar/avatar_customizer_screen.dart';
import '../../features/badges/badges_screen.dart';
import '../../features/friends/friends_screen.dart';
import '../../features/history/receipt_history_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/insights/insights_detail_screen.dart';
import '../../features/leaderboard/leaderboard_screen.dart';
import '../../features/map/spend_map_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/places/place_picker_screen.dart';
import '../../features/places/places_search_screen.dart';
import '../../features/profile_setup/profile_setup_screen.dart';
import '../../domain/logic/merchant_extractor.dart';
import '../../domain/models/transaction_view.dart';
import '../../features/pending_imports/pending_imports_screen.dart';
import '../../features/receipt_saved/batch_receipt_saved_screen.dart';
import '../../features/receipt_saved/receipt_saved_screen.dart';
import '../../features/review/receipt_review_screen.dart';
import '../../features/bill_split/split_requests_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/share/share_hint_screen.dart';
import '../../features/tx_detail/transaction_detail_screen.dart';
import '../../widgets/main_shell.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// Builds the router with auth + onboarding redirects.
GoRouter createAppRouter(AuthRefreshNotifier refresh) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;

      if (Env.skipAuth) {
        if (path == '/auth' ||
            path == '/onboarding' ||
            path == '/profile-setup') {
          return '/home';
        }
        return null;
      }

      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final onboardingDone = AppPrefs.onboardingComplete;
      final profileSetupDone = AppPrefs.profileSetupComplete;

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
      if (loggedIn && !profileSetupDone && path != '/profile-setup') {
        return '/profile-setup';
      }
      if (loggedIn &&
          profileSetupDone &&
          (path == '/auth' ||
              path == '/onboarding' ||
              path == '/profile-setup')) {
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
                path: '/ranks',
                name: 'ranks',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: LeaderboardScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                name: 'profile',
                pageBuilder: (context, state) =>
                    const NoTransitionPage<void>(child: SettingsScreen()),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/insights',
        name: 'insights',
        builder: (context, state) => const InsightsDetailScreen(),
      ),
      // Legacy alias — Profile is a shell tab at /profile now.
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings',
        name: 'settings',
        redirect: (context, state) => '/profile',
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/avatar',
        name: 'avatar',
        builder: (context, state) => const AvatarCustomizerScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/badges',
        name: 'badges',
        builder: (context, state) => const BadgesScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/history',
        name: 'history',
        builder: (context, state) => const ReceiptHistoryScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/receipt-saved',
        name: 'receipt-saved',
        builder: (context, state) {
          final tx = state.extra as TransactionView?;
          return ReceiptSavedScreen(receipt: tx!);
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/batch-saved',
        name: 'batch-saved',
        builder: (context, state) {
          final txs = state.extra as List<TransactionView>;
          return BatchReceiptSavedScreen(receipts: txs);
        },
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
        path: '/profile-setup',
        name: 'profile-setup',
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/friends',
        name: 'friends',
        builder: (context, state) => const FriendsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/tx/:id',
        name: 'tx-detail',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final editable = state.uri.queryParameters['edit'] == '1';
          return TransactionDetailScreen(
            transactionId: id,
            editable: editable,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/places-search',
        name: 'places-search',
        builder: (context, state) => const PlacesSearchScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/place-picker',
        name: 'place-picker',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return PlacePickerScreen(
            lat: args['lat'] as double,
            lng: args['lng'] as double,
            candidates:
                args['candidates'] as List<MerchantCandidate>? ?? const [],
            merchantName: args['merchantName'] as String?,
            category: args['category'] as String?,
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/review',
        name: 'review',
        builder: (context, state) => const ReceiptReviewScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/pending-imports',
        name: 'pending-imports',
        builder: (context, state) => const PendingImportsScreen(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/split-requests',
        name: 'split-requests',
        builder: (context, state) => const SplitRequestsScreen(),
      ),
    ],
  );
}
