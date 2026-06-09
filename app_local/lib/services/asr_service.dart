import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';

class AsrService {
  Future<String> transcribe(File audioFile, AppConfig config) async {
    if (!config.asrReady) {
      throw Exception('请先在设置中配置语音识别网关地址');
    }
    final base = config.asrGatewayUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/transcribe');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', audioFile.path));
    request.fields['language'] = config.asrLanguage;
    if (config.asrGatewayApiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer ${config.asrGatewayApiKey}';
    }
    final streamed = await request.send().timeout(const Duration(seconds: 180));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode >= 400) {
      throw Exception('ASR ${response.statusCode}: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['text'] ?? '').toString().trim();
  }
}
