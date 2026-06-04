import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Registers a saved FCM device token with the backend after login/startup.
class PushService {
  static const _prefsKey = 'fcm_device_token';

  static Future<void> saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, token);
  }

  static Future<String?> loadTokenLocally() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
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
      // Token registration is best-effort until FCM is fully configured.
    }
  }
}
