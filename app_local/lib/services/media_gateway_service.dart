import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';

class MediaGatewayService {
  Future<String> uploadImage(File file, AppConfig config) async {
    final base = config.mediaGatewayUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/upload');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', file.path));
    if (config.mediaGatewayApiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${config.mediaGatewayApiKey}';
    }
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) {
      throw Exception('上传失败 ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['success'] != true) {
      throw Exception(data['message'] ?? '上传失败');
    }
    return data['url'] as String;
  }
}
