import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';

class VisionItem {
  final String label;
  final String? brand;
  final String? color;
  final String? category;
  final String? purpose;
  final String rawText;

  VisionItem({
    required this.label,
    this.brand,
    this.color,
    this.category,
    this.purpose,
    this.rawText = '',
  });
}

class VisionService {
  Future<List<VisionItem>> recognize(String imageUrl, AppConfig config) async {
    if (!config.visionReady) {
      throw Exception('请先在设置中配置图像识别 API Key');
    }
    switch (config.visionProvider) {
      case 'qwen_tenant':
        return _qwenTenant(imageUrl, config);
      case 'openai_compatible':
        return _openaiCompatible(imageUrl, config);
      default:
        return _qwenTenant(imageUrl, config);
    }
  }

  Future<List<VisionItem>> _qwenTenant(String imageUrl, AppConfig config) async {
    final body = {
      'msgList': [
        {
          'msgRole': 'USER',
          'msgContent': config.visionPrompt,
          'imageFileUrls': [imageUrl],
        }
      ],
      'model': config.visionModel,
      'tenantId': config.visionTenantId,
      'modelOption': {'temperature': 1},
      'apiKey': config.visionApiKey,
    };
    final response = await http
        .post(
          Uri.parse(config.visionApiUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode >= 400) {
      throw Exception('视觉 API ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['message'] ?? '识别失败');
    }
    final content = (data['data']?['content'] ?? '').toString();
    return _parseContent(content);
  }

  Future<List<VisionItem>> _openaiCompatible(String imageUrl, AppConfig config) async {
    final response = await http
        .post(
          Uri.parse(config.visionApiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${config.visionApiKey}',
          },
          body: jsonEncode({
            'model': config.visionModel,
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': config.visionPrompt},
                  {'type': 'image_url', 'image_url': {'url': imageUrl}},
                ],
              }
            ],
            'max_tokens': 2048,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode >= 400) {
      throw Exception('视觉 API ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['choices']?[0]?['message']?['content']?.toString() ?? '';
    return _parseContent(content);
  }

  List<VisionItem> _parseContent(String content) {
    if (content.trim().isEmpty) return [];

    final items = <VisionItem>[];
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty);

    for (final line in lines) {
      final cleaned = line
          .replaceAll(RegExp(r'^[-*•\d.]+\s*'), '')
          .replaceAll(RegExp(r'\*\*'), '')
          .trim();
      if (cleaned.isEmpty) continue;

      // 格式：名称|品牌|颜色|分类|用途
      if (cleaned.contains('|')) {
        final parts = cleaned.split('|').map((e) => e.trim()).toList();
        items.add(VisionItem(
          label: parts.isNotEmpty ? parts[0] : cleaned,
          brand: parts.length > 1 ? _nullIfEmpty(parts[1]) : null,
          color: parts.length > 2 ? _nullIfEmpty(parts[2]) : null,
          category: parts.length > 3 ? _nullIfEmpty(parts[3]) : null,
          purpose: parts.length > 4 ? _nullIfEmpty(parts[4]) : null,
          rawText: line,
        ));
        continue;
      }

      // 解析「物品名称：无线鼠标」类字段
      final label = _extractField(cleaned, ['物品名称', '名称', 'label']);
      final brand = _extractField(cleaned, ['品牌型号', '品牌', 'brand']);
      final color = _extractField(cleaned, ['颜色', 'color']);
      final category = _extractField(cleaned, ['分类', 'category']);
      final purpose = _extractField(cleaned, ['用途', 'purpose']);

      if (label != null || !cleaned.contains('：') && !cleaned.contains(':')) {
        items.add(VisionItem(
          label: label ?? cleaned,
          brand: brand,
          color: color,
          category: category,
          purpose: purpose,
          rawText: line,
        ));
      }
    }

    if (items.isEmpty) {
      items.add(VisionItem(label: content.split('\n').first.trim(), rawText: content));
    }
    return items;
  }

  String? _extractField(String text, List<String> keys) {
    for (final k in keys) {
      final re = RegExp('${RegExp.escape(k)}[：:]([^，,。.\\n]+)');
      final m = re.firstMatch(text);
      if (m != null) return m.group(1)?.trim();
    }
    return null;
  }

  String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
}
