import 'package:flutter/material.dart';
import '../services/api_client.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _api = ApiClient();
  List<dynamic> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.get('/auth/users');
      setState(() { _users = data is List ? data : []; });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _addUser() async {
    final userCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加用户'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: userCtrl, decoration: const InputDecoration(labelText: '用户名')),
          TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: '邮箱')),
          TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.post('/auth/users', body: {'username': userCtrl.text, 'email': emailCtrl.text, 'password': passCtrl.text});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteUser(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除用户'),
        content: Text('确定删除「$name」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.delete('/auth/users/$id');
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: oldCtrl, obscureText: true, decoration: const InputDecoration(labelText: '当前密码')),
          const SizedBox(height: 8),
          TextField(controller: newCtrl, obscureText: true, decoration: const InputDecoration(labelText: '新密码')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.post('/auth/change-password', body: {'old_password': oldCtrl.text, 'new_password': newCtrl.text});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已修改')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('用户管理'), actions: [
        IconButton(icon: const Icon(Icons.lock_outline), tooltip: '修改密码', onPressed: _changePassword),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _addUser, child: const Icon(Icons.person_add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                return ListTile(
                  leading: CircleAvatar(child: Text((u['username'] ?? '?')[0].toUpperCase())),
                  title: Text(u['username'] ?? ''),
                  subtitle: Text(u['email'] ?? ''),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _deleteUser(u['id'], u['username'])),
                );
              },
            ),
    );
  }
}
