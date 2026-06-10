import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';
import '../utils/space_actions.dart';
import 'floor_plan_screen.dart';

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
  String? _navZoneId;
  String? _navContainerId;
  String? _highlightSlotId;
  String? _highlightZoneId;
  String? _lastHandledFocus;
  String? _lastHandledZoneFocus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.get('/space/locations');
      final list = data is List ? data : [];
      setState(() { _locations = list; });
      if (list.isNotEmpty && mounted) {
        final app = context.read<AppState>();
        final activeId = app.activeLocationId;
        final stillValid = activeId.isNotEmpty && list.any((l) => l['id'] == activeId);
        if (!stillValid) {
          app.setActiveLocation(list[0]['id'], list[0]['name'] ?? '');
        }
      }
    } catch (e) {
      setState(() { _error = '$e'; });
    }
    setState(() => _loading = false);
  }

  Future<void> _navigateToSlot(String slotId) async {
    try {
      final path = await _api.get('/space/slots/$slotId/path');
      setState(() {
        _navZoneId = path['zone_id'];
        _navContainerId = path['container_id'];
        _highlightSlotId = slotId;
      });
      context.read<AppState>().setActiveLocation(path['location_id'], path['location_name'] ?? '');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('定位失败: $e')));
      }
    }
  }

  Future<void> _applyTemplate(String locationId) async {
    try {
      final r = await _api.post('/space/locations/$locationId/apply-template');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已应用模板，新增 ${r['slots_created'] ?? 0} 个层级')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<int> _itemCount({String? locationId, String? zoneId, String? containerId, String? slotId}) async {
    final params = <String>[];
    if (slotId != null) params.add('slot_id=$slotId');
    if (containerId != null) params.add('container_id=$containerId');
    if (zoneId != null) params.add('zone_id=$zoneId');
    if (locationId != null) params.add('location_id=$locationId');
    try {
      final data = await _api.get('/space/item-count?${params.join('&')}');
      return (data['count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
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
        final loc = await _api.post('/space/locations', body: {'name': ctrl.text, 'is_default': _locations.isEmpty});
        if (mounted) {
          final apply = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('应用标准模板？'),
              content: const Text('可为新地点一键创建客厅、主卧、厨房等分区与储物模块。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('跳过')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('应用')),
              ],
            ),
          );
          if (apply == true && loc is Map) {
            await _applyTemplate(loc['id']);
          }
        }
        _load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final focus = app.focusSlotId;
    if (focus != null && focus != _lastHandledFocus) {
      _lastHandledFocus = focus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _navigateToSlot(focus);
          app.clearFocusSlot();
        }
      });
    }

    final focusZone = app.focusZoneId;
    if (focusZone != null && focusZone != _lastHandledZoneFocus) {
      _lastHandledZoneFocus = focusZone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _navZoneId = focusZone;
            _highlightZoneId = focusZone;
            _navContainerId = null;
            _highlightSlotId = null;
          });
          app.clearFocusZone();
        }
      });
    }

    final activeId = app.activeLocationId;

    return Scaffold(
      appBar: AppBar(title: const Text('空间管理'), actions: [
        IconButton(icon: const Icon(Icons.map_outlined), tooltip: '平面图', onPressed: () => openFloorPlan(context)),
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
                  : Column(
                      children: [
                        if (_locations.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                            child: Row(children: [
                              const Icon(Icons.place, size: 18, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: activeId.isNotEmpty ? activeId : null,
                                  decoration: const InputDecoration(
                                    labelText: '当前地点',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _locations.map<DropdownMenuItem<String>>((l) {
                                    return DropdownMenuItem(
                                      value: l['id'],
                                      child: Text(l['name'] ?? l['id']),
                                    );
                                  }).toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    final loc = _locations.firstWhere((l) => l['id'] == v);
                                    app.setActiveLocation(v, loc['name'] ?? '');
                                  },
                                ),
                              ),
                            ]),
                          ),
                        if (_highlightSlotId != null || _highlightZoneId != null)
                          MaterialBanner(
                            content: Text(_highlightSlotId != null
                                ? '已从搜索/平面图定位到层级（高亮显示）'
                                : '已从平面图定位到分区（高亮显示）'),
                            leading: const Icon(Icons.my_location),
                            actions: [
                              TextButton(
                                onPressed: () => setState(() {
                                  _highlightSlotId = null;
                                  _highlightZoneId = null;
                                }),
                                child: const Text('关闭'),
                              ),
                            ],
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Text(
                            '结构：地点 / 分区 / 模块 / 层级（长按重命名或删除）',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 80),
                                    itemCount: _locations.length,
                                    itemBuilder: (_, i) {
                                      final loc = _locations[i];
                                      return _LocationTile(
                                        loc: loc,
                                        api: _api,
                                        itemCount: _itemCount,
                                        onRefresh: _load,
                                        onApplyTemplate: () => _applyTemplate(loc['id']),
                                        initiallyExpanded: true,
                                        navZoneId: _navZoneId,
                                        navContainerId: _navContainerId,
                                        highlightSlotId: _highlightSlotId,
                                        highlightZoneId: _highlightZoneId,
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

// ---- Location Tile ----
class _LocationTile extends StatefulWidget {
  final dynamic loc;
  final ApiClient api;
  final Future<int> Function({String? locationId, String? zoneId, String? containerId, String? slotId}) itemCount;
  final VoidCallback onRefresh;
  final VoidCallback onApplyTemplate;
  final bool initiallyExpanded;
  final String? navZoneId;
  final String? navContainerId;
  final String? highlightSlotId;
  final String? highlightZoneId;

  const _LocationTile({
    required this.loc,
    required this.api,
    required this.itemCount,
    required this.onRefresh,
    required this.onApplyTemplate,
    this.initiallyExpanded = false,
    this.navZoneId,
    this.navContainerId,
    this.highlightSlotId,
    this.highlightZoneId,
  });

  @override
  State<_LocationTile> createState() => _LocationTileState();
}

class _LocationTileState extends State<_LocationTile> {
  List<dynamic>? _zones;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadZones());
    }
  }

  Future<void> _loadZones() async {
    if (_zones != null) return;
    try {
      final data = await widget.api.get('/space/zones?location_id=${widget.loc['id']}');
      setState(() { _zones = data is List ? data : []; });
    } catch (_) {
      setState(() => _zones = []);
    }
  }

  Future<void> _manageLocation() async {
    final id = widget.loc['id']?.toString() ?? '';
    final name = widget.loc['name']?.toString() ?? '';
    final count = await widget.itemCount(locationId: id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '地点',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.api.put('/space/locations/$id', body: {'name': newName});
        widget.onRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已重命名为: $newName')));
        }
      },
      onDelete: () async {
        await widget.api.delete('/space/locations/$id');
        widget.onRefresh();
        if (mounted) {
          context.read<AppState>().refreshSearchItems();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('地点已删除')));
        }
      },
    );
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
        initiallyExpanded: widget.initiallyExpanded,
        leading: const Icon(Icons.location_city, color: Colors.blue),
        title: _LongPressTitle(
          title: widget.loc['name'] ?? '',
          subtitle: widget.loc['family_name'] != null
              ? '地点 · 家庭：${widget.loc['family_name']} · ${widget.loc['zone_count'] ?? 0} 个分区'
              : '地点 · ${widget.loc['zone_count'] ?? 0} 个分区',
          onLongPress: _manageLocation,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.dashboard_customize, size: 20),
          tooltip: '应用模板',
          onPressed: widget.onApplyTemplate,
        ),
        onExpansionChanged: (exp) { if (exp) _loadZones(); },
        children: [
          if (_zones != null)
            for (final z in _zones!)
              _ZoneTile(
                zone: z,
                api: widget.api,
                itemCount: widget.itemCount,
                initiallyExpanded: z['id'] == widget.navZoneId,
                navContainerId: widget.navContainerId,
                highlightSlotId: widget.highlightSlotId,
                highlightZoneId: widget.highlightZoneId,
                onChanged: () {
                  setState(() => _zones = null);
                  _loadZones();
                },
              ),
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
  final Future<int> Function({String? locationId, String? zoneId, String? containerId, String? slotId}) itemCount;
  final bool initiallyExpanded;
  final String? navContainerId;
  final String? highlightSlotId;
  final String? highlightZoneId;
  final VoidCallback onChanged;

  const _ZoneTile({
    required this.zone,
    required this.api,
    required this.itemCount,
    this.initiallyExpanded = false,
    this.navContainerId,
    this.highlightSlotId,
    this.highlightZoneId,
    required this.onChanged,
  });

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  List<dynamic>? _containers;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadContainers());
    }
  }

  Future<void> _loadContainers() async {
    if (_containers != null) return;
    try {
      final data = await widget.api.get('/space/containers?zone_id=${widget.zone['id']}');
      setState(() { _containers = data is List ? data : []; });
    } catch (_) {
      setState(() => _containers = []);
    }
  }

  Future<void> _manageZone() async {
    final id = widget.zone['id']?.toString() ?? '';
    final name = widget.zone['name']?.toString() ?? '';
    final count = await widget.itemCount(zoneId: id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '分区',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.api.put('/space/zones/$id', body: {'name': newName});
        widget.onChanged();
      },
      onDelete: () async {
        await widget.api.delete('/space/zones/$id');
        widget.onChanged();
        if (mounted) {
          context.read<AppState>().refreshSearchItems();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分区已删除')));
        }
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.zone['id'] == widget.highlightZoneId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: highlighted ? Colors.amber.shade50 : null,
        shape: highlighted
            ? RoundedRectangleBorder(side: BorderSide(color: Colors.orange.shade400, width: 2))
            : null,
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded || highlighted,
          leading: const Icon(Icons.crop_square, size: 20),
          title: _LongPressTitle(
            title: widget.zone['name'] ?? '',
            subtitle: '分区',
            onLongPress: _manageZone,
          ),
          onExpansionChanged: (exp) { if (exp) _loadContainers(); },
          trailing: IconButton(icon: const Icon(Icons.add, size: 18), onPressed: _addContainer),
          children: [
            if (_containers != null) ...[
              if (_containers!.isEmpty)
                const Padding(padding: EdgeInsets.all(12), child: Text('暂无储物模块', style: TextStyle(color: Colors.grey, fontSize: 13)))
              else
                for (final c in _containers!)
                  _ContainerTile(
                    container: c,
                    api: widget.api,
                    itemCount: widget.itemCount,
                    initiallyExpanded: c['id'] == widget.navContainerId,
                    highlightSlotId: widget.highlightSlotId,
                    onChanged: () {
                      setState(() => _containers = null);
                      _loadContainers();
                      widget.onChanged();
                    },
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

// ---- Container Tile ----
class _ContainerTile extends StatefulWidget {
  final dynamic container;
  final ApiClient api;
  final Future<int> Function({String? locationId, String? zoneId, String? containerId, String? slotId}) itemCount;
  final bool initiallyExpanded;
  final String? highlightSlotId;
  final VoidCallback onChanged;

  const _ContainerTile({
    required this.container,
    required this.api,
    required this.itemCount,
    required this.onChanged,
    this.initiallyExpanded = false,
    this.highlightSlotId,
  });

  @override
  State<_ContainerTile> createState() => _ContainerTileState();
}

class _ContainerTileState extends State<_ContainerTile> {
  Future<void> _manageContainer() async {
    final id = widget.container['id']?.toString() ?? '';
    final name = widget.container['name']?.toString() ?? '';
    final count = await widget.itemCount(containerId: id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '储物模块',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.api.put('/space/containers/$id', body: {'name': newName});
        widget.onChanged();
      },
      onDelete: () async {
        await widget.api.delete('/space/containers/$id');
        widget.onChanged();
        if (mounted) {
          context.read<AppState>().refreshSearchItems();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('储物模块已删除')));
        }
      },
    );
  }

  Future<void> _addSlot() async {
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
        await widget.api.post('/space/containers/${widget.container['id']}/slots', body: [
          {'name': ctrl.text, 'level': 1},
        ]);
        widget.onChanged();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = (widget.container['slots'] as List?) ?? [];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Card(
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          leading: const Icon(Icons.cabin, size: 18),
          title: _LongPressTitle(
            title: widget.container['name'] ?? '',
            subtitle: '储物模块 · ${slots.length} 个层级',
            onLongPress: _manageContainer,
          ),
          children: [
            for (final s in slots)
              _SlotItemsTile(
                slot: s,
                api: widget.api,
                itemCount: widget.itemCount,
                highlighted: s['id'] == widget.highlightSlotId,
                onChanged: widget.onChanged,
              ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.add, color: Colors.green, size: 16),
              title: const Text('添加层级', style: TextStyle(fontSize: 13)),
              onTap: _addSlot,
            ),
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
  final Future<int> Function({String? locationId, String? zoneId, String? containerId, String? slotId}) itemCount;
  final VoidCallback onChanged;
  final bool highlighted;

  const _SlotItemsTile({
    required this.slot,
    required this.api,
    required this.itemCount,
    required this.onChanged,
    this.highlighted = false,
  });

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

  Future<void> _manageSlot() async {
    final id = widget.slot['id']?.toString() ?? '';
    final name = widget.slot['name']?.toString() ?? '';
    final count = await widget.itemCount(slotId: id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '层级',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.api.put('/space/slots/$id', body: {'name': newName});
        widget.onChanged();
      },
      onDelete: () async {
        await widget.api.delete('/space/slots/$id');
        widget.onChanged();
        if (mounted) {
          context.read<AppState>().refreshSearchItems();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('层级已删除')));
        }
      },
    );
  }

  Future<void> _markReturned(String itemId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('归位「$label」'),
        content: const Text('确认该物品已归还？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('已归位')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/reminders/borrow/return', body: {'item_id': itemId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已标记归位')));
      }
      setState(() => _items = null);
      await _loadItems();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _editItemTags(dynamic it) async {
    final current = List<String>.from((it['tags'] as List?)?.map((e) => e.toString()) ?? []);
    final selected = <String>{...current};
    const presets = ['老家', '送人'];
    final customCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('标记「${it['label'] ?? ''}」'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择或添加标记，便于后续按标记搜索与批量归档'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final p in presets)
                      FilterChip(
                        label: Text(p),
                        selected: selected.contains(p),
                        onSelected: (v) => setDlg(() {
                          if (v) {
                            selected.add(p);
                          } else {
                            selected.remove(p);
                          }
                        }),
                      ),
                    for (final t in selected.where((t) => !presets.contains(t)))
                      FilterChip(
                        label: Text(t),
                        selected: true,
                        onSelected: (_) => setDlg(() => selected.remove(t)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: customCtrl,
                        decoration: const InputDecoration(
                          labelText: '自定义标记',
                          hintText: '如：捐赠、二手',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final v = customCtrl.text.trim();
                        if (v.isNotEmpty) {
                          setDlg(() {
                            selected.add(v);
                            customCtrl.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.patch('/items/${it['id']}/tags', body: {'tags': selected.toList()});
      if (mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标记已更新')));
      }
      setState(() => _items = null);
      await _loadItems();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _showItemActions(dynamic it) {
    final borrowed = it['is_borrowed'] == true;
    final tags = (it['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(it['label'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (borrowed && it['borrower'] != null) Text('借给：${it['borrower']}'),
                  if (tags.isNotEmpty) Text('标记：${tags.join('、')}', style: TextStyle(color: Colors.orange.shade800)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.label_outline, color: Colors.orange),
              title: const Text('添加/编辑标记'),
              onTap: () {
                Navigator.pop(ctx);
                _editItemTags(it);
              },
            ),
            if (borrowed)
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.green),
                title: const Text('标记已归位'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markReturned(it['id'], it['label'] ?? '');
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.orange),
                title: const Text('标记借出'),
                onTap: () {
                  Navigator.pop(ctx);
                  _markBorrowed(it['id'], it['label'] ?? '');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除物品', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteItem(it['id'], it['label'] ?? '');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteItem(String itemId, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物品'),
        content: Text('确定归档「$label」？将从日常列表隐藏，可在检索页「历史记录」中查找。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.delete('/items/$itemId');
      if (mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已归档 $label')));
      }
      setState(() => _items = null);
      await _loadItems();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _markBorrowed(String itemId, String label) async {
    final borrowerCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('借出「$label」'),
        content: TextField(
          controller: borrowerCtrl,
          decoration: const InputDecoration(labelText: '借给谁（可选）'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认借出')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.post('/reminders/borrow', body: {
        'item_id': itemId,
        'borrower': borrowerCtrl.text.trim().isEmpty ? null : borrowerCtrl.text.trim(),
        'expected_return_hours': 24,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已标记借出，24小时后可提醒归位')));
      }
      setState(() => _items = null);
      await _loadItems();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
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
        color: widget.highlighted ? Colors.amber.shade50 : Colors.grey.shade50,
        shape: widget.highlighted
            ? RoundedRectangleBorder(side: BorderSide(color: Colors.orange.shade400, width: 2))
            : null,
        child: ExpansionTile(
          dense: true,
          leading: const Icon(Icons.grid_view, size: 16),
          title: _LongPressTitle(
            title: widget.slot['name'] ?? '',
            subtitle: _loading
                ? '层级 · 加载中...'
                : itemCount != null
                    ? '层级 ${widget.slot['level'] ?? 0} · $itemCount 件物品'
                    : '层级 ${widget.slot['level'] ?? 0}',
            onLongPress: _manageSlot,
            compact: true,
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
                      if ((it['tags'] as List?)?.isNotEmpty == true)
                        (it['tags'] as List).join('、'),
                      if (it['category'] != null) it['category'],
                      if (it['brand'] != null) '品牌: ${it['brand']}',
                      if (it['is_chargeable'] == true) '需充电',
                      if (it['is_borrowed'] == true) '已借出',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Icon(
                    it['is_borrowed'] == true ? Icons.logout : Icons.more_horiz,
                    size: 16,
                    color: it['is_borrowed'] == true ? Colors.orange : Colors.grey,
                  ),
                  onTap: () => _showItemActions(it),
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

class _LongPressTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onLongPress;
  final bool compact;

  const _LongPressTitle({
    required this.title,
    required this.subtitle,
    required this.onLongPress,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: compact ? FontWeight.normal : FontWeight.bold,
              fontSize: compact ? 13 : null,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(fontSize: compact ? 11 : 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}
