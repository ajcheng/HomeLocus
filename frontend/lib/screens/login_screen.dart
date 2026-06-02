import 'package:flutter/material.dart';
import '../services/api_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController(text: 'admin');
  final _passCtrl = TextEditingController(text: 'admin');
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    try {
      final api = ApiClient();
      final data = await api.post('/auth/login', body: {
        'username': _userCtrl.text,
        'password': _passCtrl.text,
      });
      final token = data['access_token'];
      final user = data['user'];
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home', arguments: {'token': token, 'user': user});
      }
    } catch (e) {
      setState(() { _error = '${e.toString().split("\n").first}'; });
      if (_error!.length > 80) _error = _error!.substring(0, 80);
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.home, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text('HomeLocus', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const Text('家庭物品存放管理系统'),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(labelText: '用户名', prefixIcon: Icon(Icons.person)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码', prefixIcon: Icon(Icons.lock)),
                    onSubmitted: (_) => _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('登录'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
