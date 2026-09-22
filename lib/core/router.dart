import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/auth_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/home/home_screen.dart';
import '../features/provider/provider_dashboard.dart';
import '../features/profile/profile_screen.dart';
import '../features/provider/provider_application_screen.dart';
import '../features/map/tracking_screen.dart';
import 'role_provider.dart';

import '../features/request/request_screen.dart';
import '../features/request/panic_mode_screen.dart';
import '../features/request/fallback_screen.dart';
import '../features/request/history_screen.dart';
import '../features/provider/incoming_request_screen.dart';

class AuthRouterNotifier extends ChangeNotifier {
  bool _isRecovering = false;
  bool get isRecovering => _isRecovering;

  AuthRouterNotifier() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _isRecovering = true;
        notifyListeners();
      } else if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.userUpdated) {
        if (_isRecovering) {
          _isRecovering = false;
          notifyListeners();
        }
      }
    });
  }

  void clearRecovery() {
    _isRecovering = false;
    notifyListeners();
  }
}

final authRouterNotifierProvider = Provider<AuthRouterNotifier>((ref) {
  final notifier = AuthRouterNotifier();
  ref.onDispose(() => notifier.dispose());
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final supabase = Supabase.instance.client;
  final userRole = ref.watch(userRoleProvider);
  final authNotifier = ref.watch(authRouterNotifierProvider);

  return GoRouter(
    initialLocation: '/auth',
    refreshListenable: authNotifier,
    routes: [
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return ForgotPasswordScreen(initialEmail: email);
        },
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final email = state.uri.queryParameters['email'];
          return ForgotPasswordScreen(
            initialEmail: email,
            isDirectReset: true,
          );
        },
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: 'apply',
            builder: (context, state) => const ProviderApplicationScreen(),
          ),
          GoRoute(
            path: 'track',
            builder: (context, state) => const TrackingScreen(),
          ),
          GoRoute(
            path: 'request',
            builder: (context, state) => const RequestScreen(),
          ),
          GoRoute(
            path: 'panic',
            builder: (context, state) => const PanicModeScreen(),
          ),
          GoRoute(
            path: 'fallback',
            builder: (context, state) => const FallbackScreen(),
          ),
          GoRoute(
            path: 'history',
            builder: (context, state) => const HistoryScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/provider',
        builder: (context, state) => const ProviderDashboard(),
      ),
      GoRoute(
        path: '/incoming/:id',
        builder: (context, state) => IncomingRequestScreen(
          requestId: state.pathParameters['id'] ?? '',
        ),
      ),
    ],
    redirect: (context, state) {
      final session = supabase.auth.currentSession;
      final location = state.matchedLocation;
      final bool isAuthRoute = location == '/auth' ||
          location == '/forgot-password' ||
          location == '/reset-password';

      // If user is undergoing password recovery (clicked link), route to /reset-password
      if (authNotifier.isRecovering && location != '/reset-password') {
        return '/reset-password';
      }

      if (session == null) {
        return isAuthRoute ? null : '/auth';
      }

      // If user is resetting password, allow them to stay on /reset-password
      if (location == '/reset-password') {
        return null;
      }

      if (isAuthRoute) {
        // Route based on role after login
        return userRole == UserRole.provider ? '/provider' : '/home';
      }

      // Guard the provider route
      if (location.startsWith('/provider') || location.startsWith('/incoming')) {
        if (userRole != UserRole.provider) {
          return '/home';
        }
      }

      return null;
    },
  );
});
