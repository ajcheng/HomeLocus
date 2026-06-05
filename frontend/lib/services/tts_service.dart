import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 搜索结果语音播报（本机 TTS，无需联网 API）
class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  String? _lastError;

  String? get lastError => _lastError;

  Future<bool> ensureReady() async {
    if (_ready) return true;
    _lastError = null;
    try {
      await _tts.awaitSpeakCompletion(true);
      final langs = await _tts.getLanguages;
      String? picked;
      for (final code in ['zh-CN', 'zh_CN', 'cmn-cn', 'zh-TW', 'zh']) {
        if (langs.contains(code)) {
          picked = code;
          break;
        }
      }
      if (picked == null && langs.isNotEmpty) {
        picked = langs.firstWhere((l) => l.toLowerCase().contains('zh'), orElse: () => langs.first);
      }
      if (picked != null) {
        await _tts.setLanguage(picked);
      }
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _ready = true;
      return true;
    } catch (e) {
      _lastError = '$e';
      debugPrint('TTS init failed: $e');
      return false;
    }
  }

  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    final ok = await ensureReady();
    if (!ok) return false;
    try {
      await _tts.stop();
      final result = await _tts.speak(text);
      return result == 1;
    } catch (e) {
      _lastError = '$e';
      return false;
    }
  }

  Future<bool> speakSearchResults(List<dynamic> results, {String? query}) async {
    if (results.isEmpty) {
      return speak(query != null && query.isNotEmpty ? '没有找到与$query相关的物品' : '没有找到相关物品');
    }
    final buf = StringBuffer();
    if (query != null && query.isNotEmpty) {
      buf.write('搜索$query，找到${results.length}个结果。');
    } else {
      buf.write('找到${results.length}个结果。');
    }
    for (var i = 0; i < results.length && i < 8; i++) {
      final r = results[i];
      final label = r['item_label'] ?? r['label'] ?? '未知';
      final where = r['breadcrumb'] ?? '';
      buf.write('第${i + 1}个，$label');
      if (where.toString().isNotEmpty) {
        buf.write('，在$where');
      }
      buf.write('。');
    }
    if (results.length > 8) {
      buf.write('其余${results.length - 8}个请查看屏幕。');
    }
    return speak(buf.toString());
  }

  Future<void> stop() => _tts.stop();
}
