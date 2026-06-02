import 'package:flutter/material.dart';
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
  String? _error;
  Map<String, List<dynamic>> _zonesCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.get('/space/locations');
      setState(() { _locations = data is List ? data : []; });
    } catch (e) {
      setState(() { _error = '$e'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _loadZones(String locId) async {
    if (_zonesCache.containsKey(locId)) return;
    try {
      final data = await _api.get('/space/zones?location_id=$locId');
      setState(() { _zonesCache[locId] = data is List ? data : []; });
    } catch (_) {}
  }

  Future<void> _addDialog(String type, String parentId, String parentLabel) async {
    final ctrl = TextEditingController();
    final labels = {'zone': '分区', 'container': '储物模块', 'slot': '层级'};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加${labels[type]}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('添加到: $parentLabel', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(hintText: '${labels[type]}名称')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok != true || ctrl.text.isEmpty) return;

    try {
      final path = type == 'zone'
          ? '/space/zones'
          : type == 'slot'
              ? '/space/containers/$parentId/slots'
              : '/space/containers';
      final body = type == 'zone'
          ? {'location_id': parentId, 'name': ctrl.text}
          : type == 'slot'
              ? [{'name': ctrl.text, 'level': 1}]
              : {'zone_id': parentId, 'name': ctrl.text, 'slots': <Map>[]};
      body is List ? await _api.post(path) : await _api.post(path, body: body as Map<String, dynamic>);
      _zonesCache.remove(parentId.startsWith('zone') ? parentId.split('_').first : parentId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteSlot(String slotId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除层级'),
        content: Text('确定删除「$name」？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.delete('/space/slots/$slotId');
        _zonesCache.clear();
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('空间管理'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final ctrl = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('创建地点'),
              content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '地点名称')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
              ],
            ),
          );
          if (ok == true && ctrl.text.isNotEmpty) {
            try {
              await _api.post('/space/locations', body: {'name': ctrl.text, 'is_default': _locations.isEmpty});
              _load();
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
            }
          }
        },
        child: const Icon(Icons.add_location_alt),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8),
                  Text('加载失败: $_error'),
                  const SizedBox(height: 8),
                  FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                ]))
              : _locations.isEmpty
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.home_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('还没有地点，点击 + 创建'),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _locations.length,
                        itemBuilder: (_, i) {
                          final loc = _locations[i];
                          return _LocationCard(
                            loc: loc,
                            api: _api,
                            zonesCache: _zonesCache,
                            onLoadZones: () => _loadZones(loc['id']),
                            onAdd: _addDialog,
                            onDeleteSlot: _deleteSlot,
                          );
                        },
                      ),
                    ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final dynamic loc;
  final ApiClient api;
  final Map<String, List<dynamic>> zonesCache;
  final VoidCallback onLoadZones;
  final Future<void> Function(String, String, String) onAdd;
  final Future<void> Function(String, String) onDeleteSlot;

  const _LocationCard({required this.loc, required this.api, required this.zonesCache, required this.onLoadZones, required this.onAdd, required this.onDeleteSlot});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: const Icon(Icons.location_city, color: Colors.blue),
        title: Text(loc['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${loc['zone_count'] ?? 0} 个分区'),
        onExpansionChanged: (expanded) { if (expanded) onLoadZones(); },
        children: [
          if (zonesCache.containsKey(loc['id']))
            for (final zone in zonesCache[loc['id']]!)
              _ZoneCard(zone: zone, api: api, onAdd: onAdd, onDeleteSlot: onDeleteSlot),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.green),
            title: const Text('添加分区'),
            onTap: () => onAdd('zone', loc['id'], loc['name'] ?? ''),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ZoneCard extends StatelessWidget {
  final dynamic zone;
  final ApiClient api;
  final Future<void> Function(String, String, String) onAdd;
  final Future<void> Function(String, String) onDeleteSlot;

  const _ZoneCard({required this.zone, required this.api, required this.onAdd, required this.onDeleteSlot});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Card(
        child: ExpansionTile(
          leading: const Icon(Icons.crop_square, size: 20),
          title: Text(zone['name'] ?? ''),
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => onAdd('container', zone['id'], zone['name'] ?? ''),
          ),
          children: [
            // Containers and slots would need another API to load
            // For now show a placeholder
            ListTile(
              leading: const Icon(Icons.add, color: Colors.green, size: 18),
              title: const Text('添加储物模块', style: TextStyle(fontSize: 14)),
              onTap: () => onAdd('container', zone['id'], zone['name'] ?? ''),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
