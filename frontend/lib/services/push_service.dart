import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// FCM push: auto-init when google-services.json is present, else manual token in settings.
class PushService {
  static const _prefsKey = 'fcm_device_token';
  static bool firebaseReady = false;

  static Future<void> saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, token);
  }

  static Future<String?> loadTokenLocally() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  /// Call once at app startup (after WidgetsFlutterBinding).
  static Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await saveTokenLocally(token);
        debugPrint('FCM token obtained (${token.length} chars)');
      }
      FirebaseMessaging.onTokenRefresh.listen((t) async {
        await saveTokenLocally(t);
        await registerIfSaved();
      });
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase not configured: $e');
      firebaseReady = false;
    }
    await registerIfSaved();
  }

  static Future<void> registerIfSaved() async {
    final token = await loadTokenLocally();
    if (token == null || token.isEmpty || ApiClient.authToken == null) return;
    try {
      await ApiClient().post('/notifications/device-token', body: {
        'token': token,
        'platform': 'android',
      });
    } catch (_) {
      // Best-effort until backend/FCM server key is configured.
    }
  }
}
