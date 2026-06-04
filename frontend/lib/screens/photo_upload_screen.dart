import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';
import 'recognition_screen.dart';

class PhotoUploadScreen extends StatefulWidget {
  const PhotoUploadScreen({super.key});
  @override
  State<PhotoUploadScreen> createState() => _PhotoUploadScreenState();
}

class _PhotoUploadScreenState extends State<PhotoUploadScreen> {
  final _api = ApiClient();
  final _picker = ImagePicker();
  List<dynamic> _locations = [];
  String? _selectedLocationId, _selectedSlotId, _selectedSlotName;
  File? _image;
  bool _uploading = false, _loading = true;

  @override
  void initState() { super.initState(); _loadLocations(); }

  Future<void> _loadLocations() async {
    try {
      final d = await _api.get('/space/locations');
      final list = d is List ? d : [];
      final activeId = context.read<AppState>().activeLocationId;
      setState(() {
        _locations = list;
        if (activeId.isNotEmpty) {
          _selectedLocationId = activeId;
        } else if (list.isNotEmpty) {
          _selectedLocationId = list[0]['id'];
          context.read<AppState>().setActiveLocation(list[0]['id'], list[0]['name'] ?? '');
        }
      });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _pickSlot(String locationId) async {
    setState(() => _selectedLocationId = locationId);
    List<dynamic> zones = [];
    try { zones = await _api.get('/space/zones?location_id=$locationId') as List; } catch (_) {}
    if (!mounted) return;

    if (zones.isEmpty) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('创建分区'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: '分区名称')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建'))],
      ));
      if (ok != true || ctrl.text.isEmpty) return;
      try { final z = await _api.post('/space/zones', body: {'location_id': locationId, 'name': ctrl.text}); zones = [z]; } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); return; }
    }
    if (!mounted) return;

    // Show dialog
    String? selZoneId;
    List<dynamic>? selContainers;
    final c1 = TextEditingController(), c2 = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => _SlotPickerDialog(
        zones: zones, zoneId: selZoneId, containers: selContainers, ctrl1: c1, ctrl2: c2,
        api: _api,
        onZoneSelected: (zid, containers) { selZoneId = zid; selContainers = containers; },
        onSlotSelected: (slotId, slotName) {
          setState(() { _selectedSlotId = slotId; _selectedSlotName = slotName; });
          Navigator.pop(ctx);
        },
        onSlotCreated: (slotId, slotName) {
          setState(() { _selectedSlotId = slotId; _selectedSlotName = slotName; });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await _picker.pickImage(source: source, maxWidth: 1920);
    if (img != null) setState(() => _image = File(img.path));
  }

  Future<void> _upload() async {
    if (_image == null || _selectedSlotId == null) return;
    setState(() => _uploading = true);
    try {
      final r = await _api.uploadFile('/items/upload', _image!, {'slot_id': _selectedSlotId!});
      final b = await r.stream.bytesToString();
      if (r.statusCode == 200) {
        final d = jsonDecode(b);
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RecognitionResultScreen(taskId: d['task_id'], slotId: _selectedSlotId!)));
      } else { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$b'))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照添加物品')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('1. 选择地点', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
        Wrap(spacing: 8, children: _locations.map((l) => ChoiceChip(
          label: Text(l['name'] ?? ''),
          selected: _selectedLocationId == l['id'],
          onSelected: (_) {
            context.read<AppState>().setActiveLocation(l['id'], l['name'] ?? '');
            _pickSlot(l['id']);
          },
        )).toList()),
        if (_selectedSlotId != null) ...[const SizedBox(height: 16), Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.check_circle, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text('位置: $_selectedSlotName')), IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _pickSlot(_selectedLocationId!))])))],
        const SizedBox(height: 20), Text('2. 拍照', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
        if (_image != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_image!, height: 250, width: double.infinity, fit: BoxFit.cover))
        else Container(height: 200, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), color: Colors.grey.shade100), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.camera_alt, size: 48, color: Colors.grey.shade400), const SizedBox(height: 8), const Text('点击下方按钮拍照或选择照片')]))),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [FilledButton.tonalIcon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera), label: const Text('拍照')), const SizedBox(width: 16), FilledButton.tonalIcon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相册'))]),
        const SizedBox(height: 24),
        SizedBox(height: 52, child: FilledButton.icon(onPressed: (_image != null && _selectedSlotId != null && !_uploading) ? _upload : null, icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload), label: Text(_uploading ? '上传中...' : '上传并识别'))),
      ])),
    );
  }
}

// Separate widget for the slot picker dialog to avoid complex inline logic
class _SlotPickerDialog extends StatefulWidget {
  final List<dynamic> zones;
  final String? zoneId;
  final List<dynamic>? containers;
  final TextEditingController ctrl1, ctrl2;
  final ApiClient api;
  final Function(String, List<dynamic>) onZoneSelected;
  final Function(String, String) onSlotSelected;
  final Function(String, String) onSlotCreated;
  const _SlotPickerDialog({required this.zones, this.zoneId, this.containers, required this.ctrl1, required this.ctrl2, required this.api, required this.onZoneSelected, required this.onSlotSelected, required this.onSlotCreated});

  @override
  State<_SlotPickerDialog> createState() => _SlotPickerDialogState();
}

class _SlotPickerDialogState extends State<_SlotPickerDialog> {
  String? _zoneId;
  List<dynamic>? _containers;
  bool _loadingContainers = false;

  Future<void> _selectZone(String zid) async {
    setState(() { _zoneId = zid; _loadingContainers = true; });
    try { final d = await widget.api.get('/space/containers?zone_id=$zid'); setState(() { _containers = d is List ? d : []; }); } catch (_) { setState(() => _containers = []); }
    setState(() => _loadingContainers = false);
    widget.onZoneSelected(zid, _containers ?? []);
  }

  Future<void> _createAndAdd() async {
    if (_zoneId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择分区'))); return; }
    if (widget.ctrl1.text.isEmpty || widget.ctrl2.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整'))); return; }
    try {
      final r = await widget.api.post('/space/containers', body: {'zone_id': _zoneId, 'name': widget.ctrl1.text, 'slots': [{'name': widget.ctrl2.text, 'level': 1}]});
      if (r is Map && r['slots'] != null && (r['slots'] as List).isNotEmpty) {
        final zn = widget.zones.firstWhere((z) => z['id'] == _zoneId)['name'];
        widget.onSlotCreated((r['slots'] as List).first['id'], '$zn / ${r['name']} / ${widget.ctrl2.text}');
      }
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext ctx) {
    return AlertDialog(
      title: const Text('选择储物位置'),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('1. 选择分区:', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 4),
        Wrap(spacing: 6, children: widget.zones.map((z) => ChoiceChip(label: Text(z['name'] ?? ''), selected: _zoneId == z['id'], onSelected: (s) { if (s) _selectZone(z['id']); })).toList()),
        if (_loadingContainers) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (_containers != null && _containers!.isNotEmpty) ...[
          const SizedBox(height: 12), const Text('已有储物模块:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ..._containers!.map((c) {
            final slots = (c['slots'] as List?) ?? [];
            return Card(child: ExpansionTile(
              leading: const Icon(Icons.cabin, size: 18), title: Text(c['name'] ?? '', style: const TextStyle(fontSize: 14)),
              children: slots.map((s) => ListTile(leading: const Icon(Icons.check_circle_outline, size: 16, color: Colors.green), title: Text(s['name'] ?? ''), onTap: () {
                final zn = widget.zones.firstWhere((z) => z['id'] == _zoneId)['name'];
                widget.onSlotSelected(s['id'], '$zn / ${c['name']} / ${s['name']}');
              })).toList(),
            ));
          }),
        ],
        const Divider(height: 24), const Text('或创建新的:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(height: 8),
        TextField(controller: widget.ctrl1, decoration: const InputDecoration(labelText: '储物模块', hintText: '如：电视柜', border: OutlineInputBorder())),
        const SizedBox(height: 8), TextField(controller: widget.ctrl2, decoration: const InputDecoration(labelText: '层级/抽屉', hintText: '如：第二层抽屉', border: OutlineInputBorder())),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: _createAndAdd, child: const Text('创建并选择'))],
    );
  }
}
