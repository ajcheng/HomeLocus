import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
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

  Future<void> _addLocation() async {
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('空间管理'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: _addLocation, child: const Icon(Icons.add_location_alt)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 8), Text(_error!),
                  FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                ]))
              : _locations.isEmpty
                  ? const Center(child: Text('还没有地点，点击 + 创建'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80),
                        itemCount: _locations.length,
                        itemBuilder: (_, i) => _LocationTile(loc: _locations[i], api: _api, onRefresh: _load),
                      ),
                    ),
    );
  }
}

// ---- Location Tile ----
class _LocationTile extends StatefulWidget {
  final dynamic loc;
  final ApiClient api;
  final VoidCallback onRefresh;
  const _LocationTile({required this.loc, required this.api, required this.onRefresh});

  @override
  State<_LocationTile> createState() => _LocationTileState();
}

class _LocationTileState extends State<_LocationTile> {
  List<dynamic>? _zones;

  Future<void> _loadZones() async {
    if (_zones != null) return;
    try {
      final data = await widget.api.get('/space/zones?location_id=${widget.loc['id']}');
      setState(() { _zones = data is List ? data : []; });
    } catch (_) {
      setState(() => _zones = []);
    }
  }

  Future<void> _deleteLocation() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地点'),
        content: Text('确定删除「${widget.loc['name']}」及其所有分区、储物模块和物品？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.delete('/space/locations/${widget.loc['id']}');
        widget.onRefresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addZone() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加分区'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '如：客厅、主卧')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await widget.api.post('/space/zones', body: {'location_id': widget.loc['id'], 'name': ctrl.text});
        setState(() => _zones = null);
        _loadZones();
        widget.onRefresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ExpansionTile(
        leading: const Icon(Icons.location_city, color: Colors.blue),
        title: Text(widget.loc['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${widget.loc['zone_count'] ?? 0} 个分区'),
        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: _deleteLocation),
        onExpansionChanged: (exp) { if (exp) _loadZones(); },
        children: [
          if (_zones != null)
            for (final z in _zones!)
              _ZoneTile(zone: z, api: widget.api),
          ListTile(leading: const Icon(Icons.add, color: Colors.green), title: const Text('添加分区'), onTap: _addZone),
        ],
      ),
    );
  }
}

// ---- Zone Tile ----
class _ZoneTile extends StatefulWidget {
  final dynamic zone;
  final ApiClient api;
  const _ZoneTile({required this.zone, required this.api});

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  List<dynamic>? _containers;

  Future<void> _loadContainers() async {
    if (_containers != null) return;
    try {
      final data = await widget.api.get('/space/containers?zone_id=${widget.zone['id']}');
      setState(() { _containers = data is List ? data : []; });
    } catch (_) {
      setState(() => _containers = []);
    }
  }

  Future<void> _addContainer() async {
    final ctrl = TextEditingController();
    final slotCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('在「${widget.zone['name']}」添加储物模块'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: '储物模块', hintText: '如：大衣柜')),
          const SizedBox(height: 8),
          TextField(controller: slotCtrl, decoration: const InputDecoration(labelText: '第一个层级', hintText: '如：第一层抽屉')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        final slots = slotCtrl.text.isNotEmpty ? [{'name': slotCtrl.text, 'level': 1}] : <Map<String, dynamic>>[];
        await widget.api.post('/space/containers', body: {'zone_id': widget.zone['id'], 'name': ctrl.text, 'slots': slots});
        setState(() => _containers = null);
        _loadContainers();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _addSlot(String containerId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加层级/抽屉'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '如：第二层抽屉')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await widget.api.post('/space/containers/$containerId/slots', body: [
          {'name': ctrl.text, 'level': 1},
        ]);
        setState(() => _containers = null);
        _loadContainers();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: ExpansionTile(
          leading: const Icon(Icons.crop_square, size: 20),
          title: Text(widget.zone['name'] ?? ''),
          onExpansionChanged: (exp) { if (exp) _loadContainers(); },
          trailing: IconButton(icon: const Icon(Icons.add, size: 18), onPressed: _addContainer),
          children: [
            if (_containers != null) ...[
              if (_containers!.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('暂无储物模块', style: TextStyle(color: Colors.grey, fontSize: 13)))
              else
                for (final c in _containers!)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.cabin, size: 18),
                        title: Text(c['name'] ?? '', style: const TextStyle(fontSize: 14)),
                        subtitle: Text('${(c['slots'] as List?)?.length ?? 0} 个层级', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        children: [
                          if (c['slots'] != null)
                            for (final s in c['slots'] as List)
                              _SlotItemsTile(slot: s, api: widget.api, onChanged: () {
                                setState(() => _containers = null);
                                _loadContainers();
                              }),
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.add, color: Colors.green, size: 16),
                            title: const Text('添加层级', style: TextStyle(fontSize: 13)),
                            onTap: () => _addSlot(c['id']),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            ListTile(
              leading: const Icon(Icons.add, color: Colors.green, size: 18),
              title: const Text('添加储物模块', style: TextStyle(fontSize: 14)),
              onTap: _addContainer,
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

// ---- Slot with items list ----
class _SlotItemsTile extends StatefulWidget {
  final dynamic slot;
  final ApiClient api;
  final VoidCallback onChanged;

  const _SlotItemsTile({required this.slot, required this.api, required this.onChanged});

  @override
  State<_SlotItemsTile> createState() => _SlotItemsTileState();
}

class _SlotItemsTileState extends State<_SlotItemsTile> {
  List<dynamic>? _items;
  bool _loading = false;

  Future<void> _loadItems() async {
    if (_items != null || _loading) return;
    setState(() => _loading = true);
    try {
      final data = await widget.api.get('/items/slot/${widget.slot['id']}');
      setState(() { _items = data is List ? data : []; });
    } catch (_) {
      setState(() => _items = []);
    }
    setState(() => _loading = false);
  }

  Future<void> _addManualItem() async {
    final labelCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    var chargeable = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('添加物品到「${widget.slot['name']}」'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: '物品名称 *')),
                TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: '品牌')),
                TextField(controller: categoryCtrl, decoration: const InputDecoration(labelText: '分类', hintText: 'electronics / clothing')),
                CheckboxListTile(
                  value: chargeable,
                  title: const Text('需充电设备'),
                  onChanged: (v) => setDlg(() => chargeable = v == true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, labelCtrl.text.trim().isNotEmpty),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    try {
      await widget.api.post('/items/manual', body: {
        'slot_id': widget.slot['id'],
        'label': labelCtrl.text.trim(),
        if (brandCtrl.text.trim().isNotEmpty) 'brand': brandCtrl.text.trim(),
        if (categoryCtrl.text.trim().isNotEmpty) 'category': categoryCtrl.text.trim(),
        'is_chargeable_device': chargeable,
        'charge_reminder_cycle_days': 90,
      });
      if (mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('物品已添加')));
      }
      setState(() => _items = null);
      await _loadItems();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _items?.length;
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: Colors.grey.shade50,
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.grid_view, size: 16),
          title: Text(widget.slot['name'] ?? '', style: const TextStyle(fontSize: 13)),
          subtitle: Text(
            _loading
                ? '加载中...'
                : itemCount != null
                    ? '层级 ${widget.slot['level'] ?? 0} · $itemCount 件物品'
                    : '层级 ${widget.slot['level'] ?? 0}',
            style: const TextStyle(fontSize: 11),
          ),
          onExpansionChanged: (exp) {
            if (exp) _loadItems();
          },
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
            else if (_items != null && _items!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('暂无物品', style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else if (_items != null)
              for (final it in _items!)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.inventory_2, size: 16, color: Colors.blue),
                  title: Text(it['label'] ?? '', style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    [
                      if (it['category'] != null) it['category'],
                      if (it['brand'] != null) '品牌: ${it['brand']}',
                      if (it['is_chargeable'] == true) '需充电',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_circle_outline, color: Colors.green, size: 18),
              title: const Text('手动添加物品', style: TextStyle(fontSize: 13)),
              onTap: _addManualItem,
            ),
          ],
        ),
      ),
    );
  }
}
