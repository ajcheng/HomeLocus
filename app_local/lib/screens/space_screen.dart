import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/item_repository.dart';
import '../services/space_repository.dart';
import '../utils/name_dialog.dart';
import '../utils/space_actions.dart';

class SpaceScreen extends StatefulWidget {
  const SpaceScreen({super.key});

  @override
  State<SpaceScreen> createState() => _SpaceScreenState();
}

class _SpaceScreenState extends State<SpaceScreen> {
  final _spaceRepo = SpaceRepository();
  final _itemRepo = ItemRepository();
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _zones = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _locations = await _spaceRepo.listLocations();
    final locId = context.read<AppState>().activeLocationId ??
        (_locations.isNotEmpty ? _locations.first['id'] as String : null);
    if (locId != null) {
      _zones = await _spaceRepo.listZones(locId);
    } else {
      _zones = [];
    }
    setState(() => _loading = false);
  }

  Future<void> _changed() async {
    context.read<AppState>().bump();
    await _load();
  }

  Future<void> _addLocation() async {
    final name = await showNameDialog(context, title: '添加住所', label: '住所名称', hint: '如：我的家、出租屋');
    if (name == null) return;
    final isFirst = _locations.isEmpty;
    final id = await _spaceRepo.createLocation(name, isDefault: isFirst);
    if (isFirst) await context.read<AppState>().setActiveLocation(id);
    await _changed();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加住所: $name')));
    }
  }

  Future<void> _addZone() async {
    final locId = context.read<AppState>().activeLocationId;
    if (locId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先添加住所')),
      );
      return;
    }
    final name = await showNameDialog(context, title: '添加空间', label: '空间名称', hint: '如：客厅、主卧、厨房');
    if (name == null) return;
    await _spaceRepo.createZone(locId, name);
    await _changed();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加空间: $name')));
    }
  }

  Future<void> _switchLocation(String? id) async {
    if (id == null) return;
    await context.read<AppState>().setActiveLocation(id);
    await _load();
  }

  Future<void> _manageLocation(String id, String name) async {
    final count = await _spaceRepo.countItemsInLocation(id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '住所',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await _spaceRepo.renameLocation(id, newName);
        await _changed();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已重命名为: $newName')));
        }
      },
      onDelete: () async {
        final wasActive = id == context.read<AppState>().activeLocationId;
        await _spaceRepo.deleteLocation(id);
        if (wasActive) {
          final locs = await _spaceRepo.listLocations();
          if (locs.isNotEmpty) {
            await context.read<AppState>().setActiveLocation(locs.first['id'] as String);
          } else {
            context.read<AppState>().clearActiveLocation();
          }
        }
        await _changed();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('住所已删除')));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locId = context.watch<AppState>().activeLocationId;
    String? locName;
    for (final l in _locations) {
      if (l['id'] == locId) {
        locName = l['name']?.toString();
        break;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: locId != null && locName != null
            ? GestureDetector(
                onLongPress: () => _manageLocation(locId!, locName!),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('空间管理'),
                    Text(locName!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              )
            : const Text('空间管理'),
        actions: [
          if (_locations.length > 1)
            PopupMenuButton<String>(
              tooltip: '切换住所',
              onSelected: _switchLocation,
              itemBuilder: (_) => [
                for (final l in _locations)
                  PopupMenuItem(
                    value: l['id'] as String,
                    child: Row(
                      children: [
                        if (l['id'] == locId) const Icon(Icons.check, size: 18),
                        if (l['id'] == locId) const SizedBox(width: 8),
                        Text(l['name']?.toString() ?? ''),
                      ],
                    ),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text(locName ?? '住所', style: const TextStyle(fontSize: 14)),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          IconButton(
            tooltip: '添加住所',
            icon: const Icon(Icons.home_work_outlined),
            onPressed: _addLocation,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addZone,
        icon: const Icon(Icons.add),
        label: const Text('添加空间'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _locations.isEmpty
              ? _EmptyHint(
                  icon: Icons.home_work_outlined,
                  title: '还没有住所',
                  subtitle: '先添加一个住所（如「我的家」），再添加空间、模块和层级',
                  actionLabel: '添加住所',
                  onAction: _addLocation,
                )
              : _zones.isEmpty
                  ? _EmptyHint(
                      icon: Icons.account_tree_outlined,
                      title: locName != null ? '$locName 还没有空间' : '还没有空间',
                      subtitle: '空间 → 模块 → 层级，例如：客厅 → 电视柜 → 上层',
                      actionLabel: '添加空间',
                      onAction: _addZone,
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text(
                            '结构：住所 / 空间 / 模块 / 层级（长按重命名或删除）',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ),
                        for (final z in _zones)
                          _ZoneTile(
                            zone: z,
                            spaceRepo: _spaceRepo,
                            itemRepo: _itemRepo,
                            onChanged: _changed,
                          ),
                      ],
                    ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _ZoneTile extends StatefulWidget {
  final Map<String, dynamic> zone;
  final SpaceRepository spaceRepo;
  final ItemRepository itemRepo;
  final VoidCallback onChanged;

  const _ZoneTile({
    required this.zone,
    required this.spaceRepo,
    required this.itemRepo,
    required this.onChanged,
  });

  @override
  State<_ZoneTile> createState() => _ZoneTileState();
}

class _ZoneTileState extends State<_ZoneTile> {
  List<Map<String, dynamic>>? _containers;

  Future<void> _load() async {
    _containers = await widget.spaceRepo.listContainers(widget.zone['id'] as String);
    if (mounted) setState(() {});
  }

  Future<void> _onLongPress() async {
    final id = widget.zone['id'] as String;
    final name = widget.zone['name']?.toString() ?? '';
    final count = await widget.spaceRepo.countItemsInZone(id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '空间',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.spaceRepo.renameZone(id, newName);
        widget.onChanged();
      },
      onDelete: () async {
        await widget.spaceRepo.deleteZone(id);
        widget.onChanged();
      },
    );
  }

  Future<void> _addContainer() async {
    final name = await showNameDialog(
      context,
      title: '添加模块',
      label: '模块名称',
      hint: '如：电视柜、衣柜、鞋柜',
    );
    if (name == null) return;
    await widget.spaceRepo.createContainer(widget.zone['id'] as String, name);
    await _load();
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加模块: $name')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: _LongPressTitle(
          title: widget.zone['name']?.toString() ?? '',
          subtitle: '空间',
          onLongPress: _onLongPress,
        ),
        onExpansionChanged: (e) {
          if (e && _containers == null) _load();
        },
        children: [
          if (_containers == null)
            const LinearProgressIndicator()
          else ...[
            for (final c in _containers!)
              _ContainerTile(
                container: c,
                spaceRepo: widget.spaceRepo,
                itemRepo: widget.itemRepo,
                onChanged: widget.onChanged,
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: Colors.green),
              title: const Text('添加模块'),
              onTap: _addContainer,
            ),
          ],
        ],
      ),
    );
  }
}

class _ContainerTile extends StatefulWidget {
  final Map<String, dynamic> container;
  final SpaceRepository spaceRepo;
  final ItemRepository itemRepo;
  final VoidCallback onChanged;

  const _ContainerTile({
    required this.container,
    required this.spaceRepo,
    required this.itemRepo,
    required this.onChanged,
  });

  @override
  State<_ContainerTile> createState() => _ContainerTileState();
}

class _ContainerTileState extends State<_ContainerTile> {
  List<Map<String, dynamic>>? _slots;

  Future<void> _load() async {
    _slots = await widget.spaceRepo.listSlots(widget.container['id'] as String);
    if (mounted) setState(() {});
  }

  Future<void> _onLongPress() async {
    final id = widget.container['id'] as String;
    final name = widget.container['name']?.toString() ?? '';
    final count = await widget.spaceRepo.countItemsInContainer(id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '模块',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.spaceRepo.renameContainer(id, newName);
        widget.onChanged();
      },
      onDelete: () async {
        await widget.spaceRepo.deleteContainer(id);
        widget.onChanged();
      },
    );
  }

  Future<void> _addSlot() async {
    final name = await showNameDialog(
      context,
      title: '添加层级',
      label: '层级名称',
      hint: '如：上层、中层、抽屉1',
    );
    if (name == null) return;
    await widget.spaceRepo.createSlot(widget.container['id'] as String, name);
    await _load();
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加层级: $name')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: _LongPressTitle(
        title: widget.container['name']?.toString() ?? '',
        subtitle: '模块',
        indent: '  ',
        onLongPress: _onLongPress,
      ),
      onExpansionChanged: (e) {
        if (e && _slots == null) _load();
      },
      children: [
        if (_slots == null)
          const LinearProgressIndicator()
        else ...[
          if (_slots!.isEmpty)
            const ListTile(
              dense: true,
              title: Text('    暂无层级，请添加'),
            ),
          for (final s in _slots!)
            _SlotTile(
              slot: s,
              spaceRepo: widget.spaceRepo,
              itemRepo: widget.itemRepo,
              onChanged: widget.onChanged,
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.green),
            title: const Text('    添加层级'),
            onTap: _addSlot,
          ),
        ],
      ],
    );
  }
}

class _SlotTile extends StatefulWidget {
  final Map<String, dynamic> slot;
  final SpaceRepository spaceRepo;
  final ItemRepository itemRepo;
  final VoidCallback onChanged;

  const _SlotTile({
    required this.slot,
    required this.spaceRepo,
    required this.itemRepo,
    required this.onChanged,
  });

  @override
  State<_SlotTile> createState() => _SlotTileState();
}

class _SlotTileState extends State<_SlotTile> {
  List<Map<String, dynamic>>? _items;

  Future<void> _load() async {
    _items = await widget.itemRepo.listBySlot(widget.slot['id'] as String);
    if (mounted) setState(() {});
  }

  Future<void> _onLongPress() async {
    final id = widget.slot['id'] as String;
    final name = widget.slot['name']?.toString() ?? '';
    final count = await widget.spaceRepo.countItemsInSlot(id);
    if (!mounted) return;
    await showRenameDeleteSheet(
      context,
      typeLabel: '层级',
      currentName: name,
      itemCount: count,
      onRename: (newName) async {
        await widget.spaceRepo.renameSlot(id, newName);
        widget.onChanged();
      },
      onDelete: () async {
        await widget.spaceRepo.deleteSlot(id);
        widget.onChanged();
      },
    );
  }

  Future<void> _addManual() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加到 ${widget.slot['name']}'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '物品名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim().isNotEmpty), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.itemRepo.insert(slotId: widget.slot['id'] as String, label: ctrl.text.trim());
    widget.onChanged();
    await _load();
  }

  Future<void> _editTags(Map<String, dynamic> it) async {
    final tags = _parseTags(it['tags']);
    final selected = tags.toSet();
    const presets = ['老家', '送人'];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('标记 ${it['label']}'),
          content: Wrap(
            spacing: 8,
            children: [
              for (final p in presets)
                FilterChip(
                  label: Text(p),
                  selected: selected.contains(p),
                  onSelected: (v) => setDlg(() => v ? selected.add(p) : selected.remove(p)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await widget.itemRepo.updateTags(it['id'] as String, selected.toList());
    widget.onChanged();
    await _load();
  }

  List<String> _parseTags(dynamic raw) {
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: _LongPressTitle(
        title: widget.slot['name']?.toString() ?? '',
        subtitle: _items != null ? '层级 · ${_items!.length} 件物品' : '层级',
        indent: '    ',
        onLongPress: _onLongPress,
      ),
      onExpansionChanged: (e) {
        if (e && _items == null) _load();
      },
      children: [
        if (_items == null)
          const LinearProgressIndicator()
        else ...[
          for (final it in _items!)
            ListTile(
              dense: true,
              title: Text(it['label']?.toString() ?? ''),
              subtitle: Text([
                if (_parseTags(it['tags']).isNotEmpty) _parseTags(it['tags']).join('、'),
                if (it['category'] != null) it['category'],
              ].join(' · ')),
              onTap: () => _editTags(it),
            ),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.green),
            title: const Text('手动添加物品'),
            onTap: _addManual,
          ),
        ],
      ],
    );
  }
}

class _LongPressTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final String indent;
  final VoidCallback onLongPress;

  const _LongPressTitle({
    required this.title,
    required this.subtitle,
    required this.onLongPress,
    this.indent = '',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$indent$title'),
          Text(
            '$indent$subtitle',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
