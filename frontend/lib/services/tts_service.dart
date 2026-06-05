import 'package:flutter_tts/flutter_tts.dart';

/// 搜索结果语音播报（适合老年人）
class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureReady();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> speakSearchResults(List<dynamic> results, {String? query}) async {
    if (results.isEmpty) {
      await speak(query != null && query.isNotEmpty ? '没有找到与$query相关的物品' : '没有找到相关物品');
      return;
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
    await speak(buf.toString());
  }

  Future<void> stop() => _tts.stop();
}
