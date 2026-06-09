/// 自定义识别服务配置（与 app_local 一致，仅存本机）
class AppConfig {
  String mediaGatewayUrl;
  String mediaGatewayApiKey;

  String visionProvider; // qwen_tenant | openai_compatible
  String visionApiUrl;
  String visionApiKey;
  String visionModel;
  String visionTenantId;
  String visionPrompt;

  String asrGatewayUrl;
  String asrGatewayApiKey;
  String asrLanguage;

  AppConfig({
    this.mediaGatewayUrl = 'https://home.ajcheng.com:8443/media',
    this.mediaGatewayApiKey = '',
    this.visionProvider = 'qwen_tenant',
    this.visionApiUrl = 'https://nfam-api.yst.com.cn/tenant/trans/call',
    this.visionApiKey = '',
    this.visionModel = 'qwen-vl-plus',
    this.visionTenantId = '',
    this.visionPrompt =
        '简洁语言输出图片物品中文名称，品牌型号（如有），颜色，用途、分类信息。每个物品一行，格式：名称|品牌|颜色|分类|用途',
    this.asrGatewayUrl = 'https://home.ajcheng.com:8443/asr',
    this.asrGatewayApiKey = '',
    this.asrLanguage = 'Chinese',
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
        mediaGatewayUrl: j['mediaGatewayUrl'] ?? 'https://home.ajcheng.com:8443/media',
        mediaGatewayApiKey: j['mediaGatewayApiKey'] ?? '',
        visionProvider: j['visionProvider'] ?? 'qwen_tenant',
        visionApiUrl: j['visionApiUrl'] ?? 'https://nfam-api.yst.com.cn/tenant/trans/call',
        visionApiKey: j['visionApiKey'] ?? '',
        visionModel: j['visionModel'] ?? 'qwen-vl-plus',
        visionTenantId: j['visionTenantId'] ?? '',
        visionPrompt: j['visionPrompt'] ??
            '简洁语言输出图片物品中文名称，品牌型号（如有），颜色，用途、分类信息。每个物品一行，格式：名称|品牌|颜色|分类|用途',
        asrGatewayUrl: j['asrGatewayUrl'] ?? 'https://home.ajcheng.com:8443/asr',
        asrGatewayApiKey: j['asrGatewayApiKey'] ?? '',
        asrLanguage: j['asrLanguage'] ?? 'Chinese',
      );

  bool get visionReady => visionApiKey.isNotEmpty && visionApiUrl.isNotEmpty;
  bool get asrReady => asrGatewayUrl.isNotEmpty;
}
