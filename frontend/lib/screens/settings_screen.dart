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
  String _provider = 'deepseek';

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
                  const Text('HomeLocus v0.1.12'),
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
