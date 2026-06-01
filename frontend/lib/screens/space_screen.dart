import 'package:flutter/material.dart';
import '../models/space.dart';
import '../services/api_client.dart';

class SpaceScreen extends StatefulWidget {
  const SpaceScreen({super.key});

  @override
  State<SpaceScreen> createState() => _SpaceScreenState();
}

class _SpaceScreenState extends State<SpaceScreen> {
  final _api = ApiClient();
  List<dynamic> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.get('/space/locations');
      setState(() { _locations = data is List ? data : []; });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _add(String type, String parentId) async {
    final name = await _getName(type);
    if (name == null || name.isEmpty) return;
    final path = {
      'location': '/space/locations',
      'zone': '/space/zones',
      'container': '/space/containers',
      'slot': '/space/containers/$parentId/slots',
    }[type]!;

    final body = type == 'zone'
        ? {'location_id': parentId, 'name': name}
        : type == 'slot'
            ? [{'name': name, 'level': 1}]
            : type == 'container'
                ? {'zone_id': parentId, 'name': name, 'slots': <Map>[]}
                : {'name': name, 'is_default': _locations.isEmpty};

    try {
      await (body is List ? _api.post(path) : _api.post(path, body: body as Map<String, dynamic>));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _getName(String type) async {
    final ctrl = TextEditingController();
    final labels = {'location': '地点', 'zone': '分区', 'container': '储物模块', 'slot': '层级'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('创建${labels[type]}'),
        content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: '输入${labels[type]}名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok == true ? ctrl.text : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('空间管理'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      floatingActionButton: PopupMenuButton<String>(
        icon: const Icon(Icons.add),
        onSelected: (t) => _add(t, ''),
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'location', child: ListTile(leading: Icon(Icons.location_city), title: Text('添加地点'))),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? const Center(child: Text('请先创建地点'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _locations.length,
                  itemBuilder: (_, i) {
                    final loc = _locations[i];
                    return _LocationTile(
                      loc: loc,
                      api: _api,
                      onAdd: _add,
                      onRefresh: _load,
                    );
                  },
                ),
    );
  }
}

class _LocationTile extends StatefulWidget {
  final dynamic loc;
  final ApiClient api;
  final Future<void> Function(String, String) onAdd;
  final VoidCallback onRefresh;

  const _LocationTile({required this.loc, required this.api, required this.onAdd, required this.onRefresh});

  @override
  State<_LocationTile> createState() => _LocationTileState();
}

class _LocationTileState extends State<_LocationTile> {
  List<dynamic>? _zones;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    try {
      final data = await widget.api.get('/space/zones?location_id=${widget.loc['id']}');
      setState(() { _zones = data is List ? data : []; });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: const Icon(Icons.home, color: Colors.blue),
        title: Text(widget.loc['name'] ?? ''),
        subtitle: Text('${widget.loc['zone_count'] ?? 0} 个分区'),
        children: [
          if (_zones != null)
            for (final z in _zones!)
              ListTile(
                leading: const Icon(Icons.crop_square),
                title: Text(z['name'] ?? ''),
                subtitle: Text(z['template_type'] ?? ''),
              ),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.green),
            title: const Text('添加分区'),
            onTap: () { widget.onAdd('zone', widget.loc['id']); _loadZones(); },
          ),
        ],
      ),
    );
  }
}
