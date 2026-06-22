import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../models/app_config.dart';
import '../models/app_settings.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _visionModelCtrl = TextEditingController();
  final _asrModelCtrl = TextEditingController();
  final _fcmTokenCtrl = TextEditingController();

  final _mediaUrl = TextEditingController();
  final _mediaKey = TextEditingController();
  final _visionUrl = TextEditingController();
  final _visionKey = TextEditingController();
  final _customVisionModel = TextEditingController();
  final _visionTenant = TextEditingController();
  final _visionPrompt = TextEditingController();
  final _asrUrl = TextEditingController();
  final _asrKey = TextEditingController();

  String _provider = 'custom';
  String _visionProvider = 'qwen_tenant';
  bool _useCustomRecognition = false;
  bool _registeringPush = false;
  bool _fieldsLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fieldsLoaded) return;
    final s = context.read<AppState>().settings;
    _bindFields(s);
    _fieldsLoaded = true;
  }

  void _bindFields(AppSettings s) {
    _serverCtrl.text = s.serverUrl;
    _provider = s.aiProvider;
    _apiKeyCtrl.text = s.aiApiKey;
    _visionModelCtrl.text = s.visionModel;
    _asrModelCtrl.text = s.asrModel;
    _useCustomRecognition = s.useCustomRecognition;

    final c = s.recognition;
    _visionProvider = c.visionProvider;
    _mediaUrl.text = c.mediaGatewayUrl;
    _mediaKey.text = c.mediaGatewayApiKey;
    _visionUrl.text = c.visionApiUrl;
    _visionKey.text = c.visionApiKey;
    _customVisionModel.text = c.visionModel;
    _visionTenant.text = c.visionTenantId;
    _visionPrompt.text = c.visionPrompt;
    _asrUrl.text = c.asrGatewayUrl;
    _asrKey.text = c.asrGatewayApiKey;
  }

  Future<void> _load() async {
    final saved = await PushService.loadTokenLocally();
    if (saved != null && saved.isNotEmpty) {
      _fcmTokenCtrl.text = saved;
    }
  }

  AppSettings _collectSettings() {
    return AppSettings(
      serverUrl: _serverCtrl.text.trim(),
      aiProvider: _provider,
      aiApiKey: _apiKeyCtrl.text.trim(),
      visionModel: _visionModelCtrl.text.trim(),
      asrModel: _asrModelCtrl.text.trim(),
      useCustomRecognition: _useCustomRecognition,
      recognition: AppConfig(
        mediaGatewayUrl: _mediaUrl.text.trim(),
        mediaGatewayApiKey: _mediaKey.text.trim(),
        visionProvider: _visionProvider,
        visionApiUrl: _visionUrl.text.trim(),
        visionApiKey: _visionKey.text.trim(),
        visionModel: _customVisionModel.text.trim(),
        visionTenantId: _visionTenant.text.trim(),
        visionPrompt: _visionPrompt.text.trim(),
        asrGatewayUrl: _asrUrl.text.trim(),
        asrGatewayApiKey: _asrKey.text.trim(),
        asrLanguage: 'Chinese',
      ),
    );
  }

  Future<void> _registerPushToken() async {
    final token = _fcmTokenCtrl.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 FCM 设备 Token')),
      );
      return;
    }
    setState(() => _registeringPush = true);
    try {
      await PushService.saveTokenLocally(token);
      await ApiClient().post('/notifications/device-token', body: {
        'token': token,
        'platform': 'android',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('推送 Token 已注册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    setState(() => _registeringPush = false);
  }

  Future<void> _save() async {
    final settings = _collectSettings();
    ApiClient.baseUrl = settings.serverUrl;
    await context.read<AppState>().saveSettings(settings);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存（识别网关配置仅存本机）')),
      );
    }
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _apiKeyCtrl.dispose();
    _visionModelCtrl.dispose();
    _asrModelCtrl.dispose();
    _fcmTokenCtrl.dispose();
    _mediaUrl.dispose();
    _mediaKey.dispose();
    _visionUrl.dispose();
    _visionKey.dispose();
    _customVisionModel.dispose();
    _visionTenant.dispose();
    _visionPrompt.dispose();
    _asrUrl.dispose();
    _asrKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            context,
            title: '服务器',
            children: [
              TextField(
                controller: _serverCtrl,
                decoration: const InputDecoration(
                  labelText: 'API 地址',
                  hintText: 'http://localhost:8000/api/v1',
                  prefixIcon: Icon(Icons.dns),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _card(
            context,
            title: 'AI 模型（服务端默认识别）',
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'deepseek', label: Text('DeepSeek')),
                  ButtonSegment(value: 'openai', label: Text('OpenAI')),
                  ButtonSegment(value: 'custom', label: Text('自定义')),
                ],
                selected: {_provider},
                onSelectionChanged: (v) => setState(() => _provider = v.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  hintText: 'sk-...',
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _visionModelCtrl,
                decoration: const InputDecoration(
                  labelText: '图片识别模型',
                  hintText: 'qwen-vl-plus / kimi-k2.5',
                  prefixIcon: Icon(Icons.image_search),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _asrModelCtrl,
                decoration: const InputDecoration(
                  labelText: '语音识别模型',
                  hintText: 'qwen3-asr / whisper-1',
                  prefixIcon: Icon(Icons.mic),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '未开启自定义识别时，语音/拍照走服务端配置（上列模型供参考记录）。',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _card(
            context,
            title: '自定义识别服务',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('使用自定义网关（覆盖服务端默认）'),
                subtitle: const Text('与单机版一致：本机直连上传/ASR/千问 VL'),
                value: _useCustomRecognition,
                onChanged: (v) => setState(() => _useCustomRecognition = v),
              ),
              const Divider(),
              Text('1. 图片上传网关', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _field(_mediaUrl, '网关地址', 'http://localhost:8780'),
              _field(_mediaKey, 'API Key（可选）', '留空则不校验'),
              const SizedBox(height: 12),
              Text('2. 图像识别（千问 VL）', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _visionProvider,
                decoration: const InputDecoration(labelText: '接入模式', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'qwen_tenant', child: Text('千问租户 API（nfam-api）')),
                  DropdownMenuItem(value: 'openai_compatible', child: Text('OpenAI 兼容 Vision')),
                ],
                onChanged: (v) => setState(() => _visionProvider = v ?? 'qwen_tenant'),
              ),
              const SizedBox(height: 8),
              _field(_visionUrl, 'API 地址', 'https://nfam-api.yst.com.cn/tenant/trans/call'),
              _field(_visionKey, 'API Key', 'sk-...'),
              _field(_customVisionModel, '模型', 'qwen-vl-plus'),
              if (_visionProvider == 'qwen_tenant')
                _field(_visionTenant, 'Tenant ID', 'ajcheng02'),
              _field(_visionPrompt, '识别提示词', null, maxLines: 3),
              const SizedBox(height: 12),
              Text('3. 语音识别网关', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _field(_asrUrl, 'ASR 网关地址', 'http://localhost:8781'),
              _field(_asrKey, 'API Key（可选）', ''),
            ],
          ),
          const SizedBox(height: 16),
          _card(
            context,
            title: '推送通知',
            children: [
              Text(
                PushService.firebaseReady
                    ? 'Firebase 已连接，Token 将自动同步。'
                    : '未检测到 google-services.json：请从 Firebase 下载配置，或手动粘贴 Token。',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _fcmTokenCtrl,
                decoration: const InputDecoration(
                  labelText: 'FCM 设备 Token',
                  hintText: '从 Firebase 或调试工具获取',
                  prefixIcon: Icon(Icons.notifications_active),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _registeringPush ? null : _registerPushToken,
                icon: _registeringPush
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.app_registration),
                label: const Text('注册推送 Token'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存设置'),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          ),
          const SizedBox(height: 32),
          _card(
            context,
            title: '关于',
            children: const [
              Text('HomeLocus v0.1.22'),
              SizedBox(height: 4),
              Text('家庭物品存放管理系统'),
              SizedBox(height: 8),
              Text('语音输入 & 模糊搜索功能由 晴晴 提出', style: TextStyle(fontStyle: FontStyle.italic)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String? hint, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
