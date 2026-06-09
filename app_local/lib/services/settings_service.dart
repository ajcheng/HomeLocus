import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';

class SettingsService {
  static const _key = 'app_config';

  Future<AppConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return AppConfig();
    return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(AppConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}
