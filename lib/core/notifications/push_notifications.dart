import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import '../network/api_client.dart';

class PushNotifications {
  PushNotifications._();

  static bool _initialized = false;
  static String? _registeredToken;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    _initialized = true;
  }

  static Future<void> register(ApiClient api) async {
    try {
      await initialize();

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null || token == _registeredToken) return;

      await api.post('/me/push-token', {'token': token, 'platform': _platform});
      _registeredToken = token;

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          await api.post('/me/push-token', {
            'token': newToken,
            'platform': _platform,
          });
          _registeredToken = newToken;
        } catch (_) {
          // Token refresh can be retried on the next app launch.
        }
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Push notification registration skipped: $error');
      }
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'unknown',
    };
  }
}
