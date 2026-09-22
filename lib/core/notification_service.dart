import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized for background processing
  await Firebase.initializeApp();
  debugPrint('Handling background FCM message: ${message.messageId}');
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final StreamController<RemoteMessage> _jobAlertController =
      StreamController<RemoteMessage>.broadcast();

  bool _initialized = false;
  String? _cachedToken;
  GoRouter? _router;

  String? get fcmToken => _cachedToken;

  /// Stream of incoming emergency jobs received while the technician has the app open
  Stream<RemoteMessage> get onJobAlert => _jobAlertController.stream;

  /// Sets the active router for navigation upon notification tap
  void setRouter(GoRouter router) {
    _router = router;
  }

  /// Initialize Firebase Messaging (permissions, handlers, token sync)
  Future<void> initialize({GoRouter? router}) async {
    if (_initialized) return;
    if (router != null) _router = router;

    // Firebase Messaging is not supported on desktop (Windows/Linux)
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux)) {
      debugPrint('Firebase Messaging is not supported on desktop.');
      _initialized = true;
      return;
    }

    try {
      // 1. Register top-level background handler (mobile only)
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      }

      // 2. Request permission (iOS & Android 13+, Web)
      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );
      debugPrint('FCM Notification permission status: ${settings.authorizationStatus}');

      // 3. Foreground presentation options (iOS / macOS only)
      if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS)) {
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // 4. Retrieve FCM token
      try {
        _cachedToken = await _fcm.getToken();
        debugPrint('FCM Device Token retrieved: $_cachedToken');
      } catch (e) {
        debugPrint('Could not retrieve FCM token on current platform: $e');
      }

      // 5. Listen for token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        syncTokenWithSupabase();
      });

      // 6. Handle notification click when app launched from terminated state
      final initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationOpen(initialMessage);
      }

      // 7. Handle notification click when app was in background
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleNotificationOpen(message);
      });

      // 8. Handle messages while app is in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Message received in foreground: ${message.notification?.title}');
        _jobAlertController.add(message);
      });

      _initialized = true;

      // Auto sync if user is already signed in
      syncTokenWithSupabase();
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  /// Syncs FCM token to current user's Supabase profile
  Future<void> syncTokenWithSupabase() async {
    try {
      if (!AppConfig.isConfigured) return;
      final user = Supabase.instance.client.auth.currentUser;
      final token = _cachedToken ?? await _fcm.getToken();
      if (user == null || token == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);

      debugPrint('Synced FCM token with Supabase profiles for ${user.id}');
    } catch (e) {
      debugPrint('FCM token sync to Supabase: $e');
    }
  }

  void _handleNotificationOpen(RemoteMessage message) {
    debugPrint('Technician tapped push notification: ${message.data}');
    final requestId = message.data['request_id']?.toString() ??
        message.data['requestId']?.toString() ??
        message.data['id']?.toString();

    if (requestId != null && requestId.isNotEmpty && _router != null) {
      _router!.push('/incoming/$requestId');
    }
  }

  void dispose() {
    _jobAlertController.close();
  }
}
