import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../models/app_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppConfig _cfg;
  final _mediaUrl = TextEditingController();
  final _mediaKey = TextEditingController();
  final _visionUrl = TextEditingController();
  final _visionKey = TextEditingController();
  final _visionModel = TextEditingController();
  final _visionTenant = TextEditingController();
  final _visionPrompt = TextEditingController();
  final _asrUrl = TextEditingController();
  final _asrKey = TextEditingController();
  String _visionProvider = 'qwen_tenant';
  bool _fieldsLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fieldsLoaded) return;
    _fieldsLoaded = true;
    _cfg = context.read<AppState>().config;
    _mediaUrl.text = _cfg.mediaGatewayUrl;
    _mediaKey.text = _cfg.mediaGatewayApiKey;
    _visionProvider = _cfg.visionProvider;
    _visionUrl.text = _cfg.visionApiUrl;
    _visionKey.text = _cfg.visionApiKey;
    _visionModel.text = _cfg.visionModel;
    _visionTenant.text = _cfg.visionTenantId;
    _visionPrompt.text = _cfg.visionPrompt;
    _asrUrl.text = _cfg.asrGatewayUrl;
    _asrKey.text = _cfg.asrGatewayApiKey;
  }

  @override
  void dispose() {
    _mediaUrl.dispose();
    _mediaKey.dispose();
    _visionUrl.dispose();
    _visionKey.dispose();
    _visionModel.dispose();
    _visionTenant.dispose();
    _visionPrompt.dispose();
    _asrUrl.dispose();
    _asrKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final c = AppConfig(
      mediaGatewayUrl: _mediaUrl.text.trim(),
      mediaGatewayApiKey: _mediaKey.text.trim(),
      visionProvider: _visionProvider,
      visionApiUrl: _visionUrl.text.trim(),
      visionApiKey: _visionKey.text.trim(),
      visionModel: _visionModel.text.trim(),
      visionTenantId: _visionTenant.text.trim(),
      visionPrompt: _visionPrompt.text.trim(),
      asrGatewayUrl: _asrUrl.text.trim(),
      asrGatewayApiKey: _asrKey.text.trim(),
      asrLanguage: _cfg.asrLanguage,
    );
    await context.read<AppState>().saveConfig(c);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存（仅存本机）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('识别服务配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('纯本地版仅需配置两个识别模型 + 图片上传网关',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _section('1. 图片上传网关', [
            _field(_mediaUrl, '网关地址', 'https://home.ajcheng.com:8443/media'),
            _field(_mediaKey, 'API Key（可选）', '留空则不校验'),
          ]),
          _section('2. 图像识别（千问 VL）', [
            DropdownButtonFormField<String>(
              value: _visionProvider,
              decoration: const InputDecoration(labelText: '接入模式'),
              items: const [
                DropdownMenuItem(value: 'qwen_tenant', child: Text('千问租户 API（nfam-api）')),
                DropdownMenuItem(value: 'openai_compatible', child: Text('OpenAI 兼容 Vision')),
              ],
              onChanged: (v) => setState(() => _visionProvider = v ?? 'qwen_tenant'),
            ),
            _field(_visionUrl, 'API 地址', 'https://nfam-api.yst.com.cn/tenant/trans/call'),
            _field(_visionKey, 'API Key', 'sk-...'),
            _field(_visionModel, '模型', 'qwen-vl-plus'),
            if (_visionProvider == 'qwen_tenant')
              _field(_visionTenant, 'Tenant ID', 'ajcheng02'),
            _field(_visionPrompt, '识别提示词', null, maxLines: 3),
          ]),
          _section('3. 语音识别网关', [
            _field(_asrUrl, 'ASR 网关地址', 'https://home.ajcheng.com:8443/asr'),
            _field(_asrKey, 'API Key（可选）', ''),
          ]),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存配置'),
          ),
          const SizedBox(height: 12),
          Text(
            '数据说明：物品、空间、照片路径均存储在手机本地；'
            '仅识别时上传图片/音频到网关，再调用大模型接口。',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: c)),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, String? hint, {int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
