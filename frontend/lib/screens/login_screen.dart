import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../services/push_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _serverCtrl = TextEditingController(text: ApiClient.baseUrl);
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'admin');
  final _apiKeyCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null && saved.isNotEmpty) {
      setState(() => _serverCtrl.text = saved);
    }
    final aiKey = prefs.getString('ai_api_key');
    if (aiKey != null) _apiKeyCtrl.text = aiKey;
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });

    // Save server URL
    final url = _serverCtrl.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    if (_apiKeyCtrl.text.isNotEmpty) {
      await prefs.setString('ai_api_key', _apiKeyCtrl.text);
    }

    try {
      final api = ApiClient(baseUrl: url);
      final data = await api.post('/auth/login', body: {
        'username': _userCtrl.text,
        'password': _passCtrl.text,
      });
      final token = data['access_token'];
      final user = data['user'];

      // Set global auth for all subsequent API calls
      ApiClient.authToken = token;
      ApiClient.baseUrl = url;
      await PushService.registerIfSaved();

      // Persist for next app launch
      await prefs.setString('auth_token', token);
      await prefs.setString('server_url', url);

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home', arguments: {'token': token, 'user': user});
      }
    } catch (e) {
      setState(() { _error = '${e.toString().split("\n").first}'; });
      if (_error!.length > 100) _error = _error!.substring(0, 100);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 420,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.home, size: 56, color: Colors.blue),
                    const SizedBox(height: 12),
                    const Text('HomeLocus', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                    const Text('家庭物品存放管理系统'),
                    const SizedBox(height: 24),

                    // ---- Server Config ----
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text('服务器设置', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _serverCtrl,
                        decoration: const InputDecoration(
                          labelText: '服务器地址',
                          hintText: 'https://your-server.com:8443/api/v1',
                          prefixIcon: Icon(Icons.dns, size: 20),
                          helperText: '域名:端口 或 /api/v1（同域部署）',
                          helperMaxLines: 2,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _apiKeyCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'AI API Key（可选）',
                          hintText: 'sk-... 或留空',
                          prefixIcon: Icon(Icons.key, size: 20),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    // ---- Login Form ----
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: '密码',
                        prefixIcon: Icon(Icons.lock),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _login(),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('登录', style: TextStyle(fontSize: 16)),
                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
