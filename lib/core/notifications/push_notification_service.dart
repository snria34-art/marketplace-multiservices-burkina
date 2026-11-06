import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../navigation/app_navigation.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  late final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  SupabaseClient? _client;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<AuthState>? _authSubscription;
  String? _currentToken;
  bool _initialized = false;

  Future<void> initialize(SupabaseClient client) async {
    _client = client;

    if (_initialized) {
      if (client.auth.currentUser != null) {
        await _registerCurrentToken();
      }
      return;
    }

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
    } catch (error, stackTrace) {
      // Firebase configuration is provisioned per real Firebase project.
      // Missing native files must disable push, not interrupt app startup.
      if (kDebugMode) {
        debugPrint('Firebase initialization unavailable; push is disabled: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return;
    }

    _messaging = FirebaseMessaging.instance;
    _initialized = true;

    await _initializeLocalNotifications();
    await _requestPermission();
    await _configureForegroundPresentation();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _messageSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => openNotificationRoute(message.data),
    );
    _tokenSubscription = _messaging.onTokenRefresh.listen((token) async {
      try {
        await _registerToken(token);
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Push token refresh registration failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    });

    _authSubscription = client.auth.onAuthStateChange.listen((state) async {
      try {
        switch (state.event) {
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
          await _registerCurrentToken();
        case AuthChangeEvent.passwordRecovery:
          break;
        case AuthChangeEvent.userDeleted:
          // The account no longer exists; avoid an RPC with a deleted session.
          _currentToken = null;
          break;
        case AuthChangeEvent.mfaChallengeVerified:
          // MFA verification does not change push-token ownership.
          break;
        case AuthChangeEvent.signedOut:
          // Supabase emits signedOut after clearing the session. A
          // user-scoped RPC cannot be authorized from this event callback.
          // Deactivation must happen in signOutAndDeactivateCurrentDevice().
          _currentToken = null;
        }
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Push auth-state synchronization failed: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
    });

    await _registerCurrentToken();

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openNotificationRoute(initial.data);
      });
    }
  }

  /// Deactivates this device token while the authenticated session still
  /// exists, then signs the user out. If the server cannot confirm
  /// deactivation, sign-out is aborted so the caller can retry safely.
  ///
  /// All app-initiated logout actions must use this method instead of
  /// calling [SupabaseClient.auth.signOut] directly.
  Future<void> signOutAndDeactivateCurrentDevice() async {
    final client = _client;
    if (client == null) {
      throw StateError('Supabase n’est pas initialisé.');
    }

    final token = _currentToken;
    if (token != null && client.auth.currentUser != null) {
      await client.rpc(
        'deactivate_notification_device',
        params: {'p_push_token': token},
      );
    }

    _currentToken = null;
    await client.auth.signOut();
  }

  Future<void> openSystemNotificationSettings() async {
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _local.openAppNotificationSettings();
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _local.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final data = jsonDecode(raw);
          if (data is Map) {
            openNotificationRoute(
              Map<String, dynamic>.from(data),
            );
          }
        } catch (_) {}
      },
    );

    const channel = AndroidNotificationChannel(
      'marketplace_default',
      'Marketplace',
      description: 'Notifications de la marketplace',
      importance: Importance.max,
    );

    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var i = 0; i < 5; i++) {
        final apnsToken = await _messaging.getAPNSToken();
        if (apnsToken != null) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> _configureForegroundPresentation() {
    return _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );
  }

  Future<void> _registerCurrentToken() async {
    if (!_initialized || _client?.auth.currentUser == null) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(token);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Push token registration unavailable: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _registerToken(String token) async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null || token.isEmpty) return;

    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'IOS'
        : 'ANDROID';

    await client.rpc(
      'register_notification_device',
      params: {
        'p_platform': platform,
        'p_push_token': token,
      },
    );

    _currentToken = token;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final data = Map<String, dynamic>.from(message.data);

    await _local.show(
      id: (message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch) & 0x7fffffff,
      title: notification.title ?? 'Marketplace Burkina',
      body: notification.body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'marketplace_default',
          'Marketplace',
          channelDescription: 'Notifications de la marketplace',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }

  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _authSubscription?.cancel();
  }
}
