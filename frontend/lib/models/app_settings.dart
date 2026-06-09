import 'app_config.dart';

/// 联网版 App 设置（服务器 + AI 模型 + 自定义识别网关）
class AppSettings {
  String serverUrl;
  String aiProvider; // deepseek | openai | custom
  String aiApiKey;
  String visionModel;
  String asrModel;
  bool useCustomRecognition;
  AppConfig recognition;

  AppSettings({
    this.serverUrl = 'https://home.ajcheng.com:8443/api/v1',
    this.aiProvider = 'custom',
    this.aiApiKey = '',
    this.visionModel = 'qwen-vl-plus',
    this.asrModel = 'qwen3-asr',
    this.useCustomRecognition = false,
    AppConfig? recognition,
  }) : recognition = recognition ?? AppConfig();

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'aiProvider': aiProvider,
        'aiApiKey': aiApiKey,
        'visionModel': visionModel,
        'asrModel': asrModel,
        'useCustomRecognition': useCustomRecognition,
        'recognition': recognition.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        serverUrl: j['serverUrl'] ?? 'https://home.ajcheng.com:8443/api/v1',
        aiProvider: j['aiProvider'] ?? 'custom',
        aiApiKey: j['aiApiKey'] ?? '',
        visionModel: j['visionModel'] ?? 'qwen-vl-plus',
        asrModel: j['asrModel'] ?? 'qwen3-asr',
        useCustomRecognition: j['useCustomRecognition'] == true,
        recognition: j['recognition'] is Map
            ? AppConfig.fromJson(j['recognition'] as Map<String, dynamic>)
            : AppConfig(),
      );
}
