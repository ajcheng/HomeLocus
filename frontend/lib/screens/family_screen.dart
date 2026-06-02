import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('创建后将自动生成家庭空间（客厅/主卧/阳台/厨房/卫生间及储物模块）', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '家庭名称', hintText: '如：陈家')),
        ]),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('家庭已创建，空间已自动生成')));
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('输入管理员分享的邀请码', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '邀请码', hintText: '输入8位邀请码')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('加入')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await _api.post('/families/join', body: {'invitation_code': ctrl.text.trim()});
        _load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入家庭')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _viewMembers(String familyId, String role, String familyName) async {
    try {
      final members = await _api.get('/families/$familyId/members') as List;
      List<dynamic> invs = [];
      if (role == 'admin') {
        try { invs = await _api.get('/families/$familyId/invitations') as List; } catch (_) {}
      }

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.85,
          minChildSize: 0.3,
          expand: false,
          builder: (ctx, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(familyName, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('成员 (${members.length})', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...members.map((m) => ListTile(
                  leading: CircleAvatar(child: Text((m['username'] ?? '?')[0].toUpperCase())),
                  title: Text(m['username'] ?? ''),
                  subtitle: Text(m['role'] == 'admin' ? '管理员' : '成员'),
                  trailing: role == 'admin' && m['role'] != 'admin'
                      ? IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () async {
                          try {
                            await _api.delete('/families/$familyId/members/${m['user_id']}');
                            if (mounted) Navigator.pop(ctx);
                            _load();
                          } catch (e) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        })
                      : null,
                )),
                if (role == 'admin') ...[
                  const Divider(height: 24),
                  Row(children: [
                    Text('邀请码 (${invs.length})', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('新建'),
                      onPressed: () async {
                        try {
                          final newInv = await _api.post('/families/$familyId/invitations', body: {'max_uses': 10});
                          setState(() => invs.insert(0, newInv));
                        } catch (e) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (invs.isEmpty)
                    const Text('暂无邀请码，点击"新建"创建', style: TextStyle(color: Colors.grey))
                  else
                    ...invs.map((inv) => Card(
                      child: ListTile(
                        title: SelectableText(inv['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 18)),
                        subtitle: Text('有效期至 ${(inv['expires_at'] ?? '').toString().substring(0, 10)} | ${inv['use_count']}/${inv['max_uses']} 已用'),
                        trailing: IconButton(
                          icon: const Icon(Icons.copy, color: Colors.blue),
                          tooltip: '复制邀请码',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inv['code'] ?? ''));
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('邀请码已复制')));
                          },
                        ),
                      ),
                    )),
                ],
              ]),
            ),
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('家庭管理'), actions: [
        IconButton(icon: const Icon(Icons.group_add), tooltip: '加入家庭', onPressed: _joinFamily),
        IconButton(icon: const Icon(Icons.add_home), tooltip: '创建家庭', onPressed: _createFamily),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _families.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('还没有家庭', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 4),
                  const Text('创建家庭将自动生成完整空间（客厅/主卧/阳台/厨房/卫生间）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _createFamily, icon: const Icon(Icons.add_home), label: const Text('创建家庭')),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _families.length,
                    itemBuilder: (_, i) {
                      final f = _families[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: f['role'] == 'admin' ? Colors.blue.shade100 : Colors.green.shade100,
                            child: Icon(f['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person, color: Colors.blue),
                          ),
                          title: Text(f['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${f['member_count']} 人 | ${f['role'] == 'admin' ? '管理员' : '成员'} | 含预设空间'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _viewMembers(f['id'], f['role'], f['name']),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
