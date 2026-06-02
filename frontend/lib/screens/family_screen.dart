import 'package:flutter/material.dart';
import '../services/api_client.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});

  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  final _api = ApiClient();
  List<dynamic> _families = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.get('/families');
      setState(() { _families = data is List ? data : []; });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _createFamily() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('创建家庭'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '家庭名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await _api.post('/families', body: {'name': ctrl.text});
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _joinFamily() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('加入家庭'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '输入邀请码')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加入')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await _api.post('/families/join', body: {'invitation_code': ctrl.text});
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _viewMembers(String familyId, String role) async {
    try {
      final members = await _api.get('/families/$familyId/members') as List;
      final invs = role == 'admin' ? await _api.get('/families/$familyId/invitations') as List : [];

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('成员 (${members.length})', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...members.map((m) => ListTile(
                    leading: CircleAvatar(child: Text((m['username'] ?? '?')[0].toUpperCase())),
                    title: Text(m['username'] ?? ''),
                    subtitle: Text(m['role'] == 'admin' ? '管理员' : '成员'),
                  )),
              if (role == 'admin') ...[
                const Divider(),
                Text('邀请码 (${invs.length})', style: Theme.of(ctx).textTheme.titleMedium),
                ...invs.map((inv) => ListTile(
                      title: SelectableText(inv['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      subtitle: Text('有效期至 ${(inv['expires_at'] ?? '').toString().substring(0, 10)} | ${inv['use_count']}/${inv['max_uses']} 已用'),
                    )),
              ],
            ],
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家庭管理'), actions: [
        IconButton(icon: const Icon(Icons.group_add), onPressed: _joinFamily),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _createFamily, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _families.isEmpty
              ? const Center(child: Text('还没有家庭，点击 + 创建'))
              : ListView.builder(
                  itemCount: _families.length,
                  itemBuilder: (_, i) {
                    final f = _families[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.people, color: Colors.blue),
                        title: Text(f['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${f['member_count']} 人 | ${f['role'] == 'admin' ? '管理员' : '成员'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _viewMembers(f['id'], f['role']),
                      ),
                    );
                  },
                ),
    );
  }
}
