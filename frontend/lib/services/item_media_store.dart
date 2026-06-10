import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 物品与本机照片/录音路径映射（仅存手机本地）
class ItemMedia {
  final String? imagePath;
  final String? audioPath;

  const ItemMedia({this.imagePath, this.audioPath});

  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;
  bool get hasAudio => audioPath != null && audioPath!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (imagePath != null) 'imagePath': imagePath,
        if (audioPath != null) 'audioPath': audioPath,
      };

  factory ItemMedia.fromJson(Map<String, dynamic> j) => ItemMedia(
        imagePath: j['imagePath'] as String?,
        audioPath: j['audioPath'] as String?,
      );
}

class ItemMediaStore {
  static const _key = 'item_media_map';

  Future<Map<String, ItemMedia>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) => MapEntry(k, ItemMedia.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<void> _saveMap(Map<String, ItemMedia> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  Future<ItemMedia?> get(String itemId) async {
    if (itemId.isEmpty) return null;
    final map = await _loadMap();
    return map[itemId];
  }

  Future<void> link({
    required String itemId,
    String? imagePath,
    String? audioPath,
  }) async {
    if (itemId.isEmpty) return;
    final map = await _loadMap();
    final existing = map[itemId] ?? const ItemMedia();
    map[itemId] = ItemMedia(
      imagePath: imagePath ?? existing.imagePath,
      audioPath: audioPath ?? existing.audioPath,
    );
    await _saveMap(map);
  }

  Future<bool> imageExists(String itemId) async {
    final media = await get(itemId);
    if (media?.imagePath == null) return false;
    return File(media!.imagePath!).exists();
  }

  Future<bool> audioExists(String itemId) async {
    final media = await get(itemId);
    if (media?.audioPath == null) return false;
    return File(media!.audioPath!).exists();
  }

  Future<Map<String, ItemMedia>> listAll() => _loadMap();

  /// imagePath -> itemId
  Future<Map<String, String>> imagePathToItemId() async {
    final map = await _loadMap();
    final out = <String, String>{};
    for (final entry in map.entries) {
      final path = entry.value.imagePath;
      if (path != null && path.isNotEmpty) {
        out[path] = entry.key;
      }
    }
    return out;
  }
}
