import 'package:flutter/material.dart';
import '../services/api_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverCtrl = TextEditingController(text: ApiClient.baseUrl);
  final _apiKeyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController(text: 'deepseek-chat');
  final _fcmTokenCtrl = TextEditingController();
  String _provider = 'deepseek';
  bool _registeringPush = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // In a full implementation, these would come from SharedPreferences
    setState(() {
      _serverCtrl.text = ApiClient.baseUrl;
    });
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
    // Update the global API base URL
    ApiClient.baseUrl = _serverCtrl.text;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存（本次会话有效）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Server
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('服务器', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _serverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API 地址',
                      hintText: 'http://192.168.1.100:8000/api/v1',
                      prefixIcon: Icon(Icons.dns),
                      helperText: '域名或IP:端口，如 https://homelocus.example.com/api/v1',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // AI
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI 模型', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
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
                    controller: _modelCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: 'deepseek-chat / gpt-4o',
                      prefixIcon: Icon(Icons.smart_toy),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('推送通知', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    '配置 FCM_SERVER_KEY 后，在 Firebase 控制台获取设备 Token 并注册，即可接收充电/借出提醒。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
            ),
          ),
          const SizedBox(height: 24),

          // Save
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('保存设置'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),

          const SizedBox(height: 32),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('HomeLocus v0.1.13'),
                  const SizedBox(height: 4),
                  const Text('家庭物品存放管理系统'),
                  const SizedBox(height: 8),
                  Text(
                    '语音输入 & 模糊搜索功能由 晴晴 提出',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
