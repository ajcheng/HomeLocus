import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsService {
  static const _key = 'app_settings';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    // 兼容旧版仅保存 server_url / ai_api_key
    return AppSettings(
      serverUrl: prefs.getString('server_url') ?? AppSettings().serverUrl,
      aiApiKey: prefs.getString('ai_api_key') ?? '',
    );
  }

  Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
    await prefs.setString('server_url', settings.serverUrl);
    if (settings.aiApiKey.isNotEmpty) {
      await prefs.setString('ai_api_key', settings.aiApiKey);
    }
  }
}
