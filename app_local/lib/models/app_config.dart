/// 纯本地 App 仅需配置两类识别服务 + 图片上传网关
class AppConfig {
  // 图片上传网关（获取 imageFileUrls）
  String mediaGatewayUrl;
  String mediaGatewayApiKey;

  // 图像识别（千问租户 / 自建）
  String visionProvider; // qwen_tenant | openai_compatible
  String visionApiUrl;
  String visionApiKey;
  String visionModel;
  String visionTenantId;
  String visionPrompt;

  // 语音识别网关
  String asrGatewayUrl;
  String asrGatewayApiKey;
  String asrLanguage;

  AppConfig({
    this.mediaGatewayUrl = const String.fromEnvironment(
      'HOMELOCUS_MEDIA_URL',
      defaultValue: 'http://localhost:8780',
    ),
    this.mediaGatewayApiKey = '',
    this.visionProvider = 'qwen_tenant',
    this.visionApiUrl = 'https://nfam-api.yst.com.cn/tenant/trans/call',
    this.visionApiKey = '',
    this.visionModel = 'qwen-vl-plus',
    this.visionTenantId = '',
    this.visionPrompt =
        '简洁语言输出图片物品中文名称，品牌型号（如有），颜色，用途、分类信息。每个物品一行，格式：名称|品牌|颜色|分类|用途',
    this.asrGatewayUrl = const String.fromEnvironment(
      'HOMELOCUS_ASR_URL',
      defaultValue: 'http://localhost:8781',
    ),
    this.asrGatewayApiKey = '',
    this.asrLanguage = 'zh',
  });

  Map<String, dynamic> toJson() => {
        'mediaGatewayUrl': mediaGatewayUrl,
        'mediaGatewayApiKey': mediaGatewayApiKey,
        'visionProvider': visionProvider,
        'visionApiUrl': visionApiUrl,
        'visionApiKey': visionApiKey,
        'visionModel': visionModel,
        'visionTenantId': visionTenantId,
        'visionPrompt': visionPrompt,
        'asrGatewayUrl': asrGatewayUrl,
        'asrGatewayApiKey': asrGatewayApiKey,
        'asrLanguage': asrLanguage,
      };

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        mediaGatewayUrl: j['mediaGatewayUrl'] ?? String.fromEnvironment(
          'HOMELOCUS_MEDIA_URL', defaultValue: 'http://localhost:8780',
        ),
        mediaGatewayApiKey: j['mediaGatewayApiKey'] ?? '',
        visionProvider: j['visionProvider'] ?? 'qwen_tenant',
        visionApiUrl: j['visionApiUrl'] ?? 'https://nfam-api.yst.com.cn/tenant/trans/call',
        visionApiKey: j['visionApiKey'] ?? '',
        visionModel: j['visionModel'] ?? 'qwen-vl-plus',
        visionTenantId: j['visionTenantId'] ?? '',
        visionPrompt: j['visionPrompt'] ??
            '简洁语言输出图片物品中文名称，品牌型号（如有），颜色，用途、分类信息',
        asrGatewayUrl: j['asrGatewayUrl'] ?? String.fromEnvironment(
          'HOMELOCUS_ASR_URL', defaultValue: 'http://localhost:8781',
        ),
        asrGatewayApiKey: j['asrGatewayApiKey'] ?? '',
        asrLanguage: j['asrLanguage'] ?? 'zh',
      );

  bool get visionReady => visionApiKey.isNotEmpty && visionApiUrl.isNotEmpty;
  bool get asrReady => asrGatewayUrl.isNotEmpty;
}
