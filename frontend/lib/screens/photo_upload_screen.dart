import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  String? _selectedLocationId;
  String? _selectedSlotId;
  String? _selectedSlotName;

  File? _image;
  bool _uploading = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final data = await _api.get('/space/locations');
      setState(() { _locations = data is List ? data : []; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickSlot(String locationId) async {
    setState(() => _selectedLocationId = locationId);

    // Load zones
    List<dynamic> zones = [];
    try {
      zones = await _api.get('/space/zones?location_id=$locationId') as List;
    } catch (_) {}

    if (!mounted) return;

    if (zones.isEmpty) {
      // No zones: create one first
      final zoneNameCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('创建分区'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('该地点还没有分区，请先创建一个', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(controller: zoneNameCtrl, autofocus: true, decoration: const InputDecoration(labelText: '分区名称', hintText: '如：客厅、主卧')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建')),
          ],
        ),
      );
      if (ok == true && zoneNameCtrl.text.isNotEmpty) {
        try {
          final zData = await _api.post('/space/zones', body: {'location_id': locationId, 'name': zoneNameCtrl.text});
          zones = [zData];
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
          return;
        }
      } else {
        return;
      }
    }

    if (!mounted) return;

    // Show zone picker + container/slot creation
    String? selectedZoneId;
    String? selectedZoneName;
    final containerCtrl = TextEditingController();
    final slotCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('选择储物位置'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('1. 选择分区:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, children: zones.map((z) => ChoiceChip(
                label: Text(z['name'] ?? ''),
                selected: selectedZoneId == z['id'],
                onSelected: (sel) {
                  setDlgState(() {
                    selectedZoneId = sel ? z['id'] : null;
                    selectedZoneName = sel ? z['name'] : null;
                  });
                },
              )).toList()),
              if (selectedZoneId == null)
                const Padding(padding: EdgeInsets.only(top: 4), child: Text('请先选择一个分区', style: TextStyle(color: Colors.red, fontSize: 12))),
              const SizedBox(height: 16),
              const Text('2. 储物模块和层级:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(controller: containerCtrl, decoration: const InputDecoration(labelText: '储物模块', hintText: '如：电视柜', border: OutlineInputBorder())),
              const SizedBox(height: 8),
              TextField(controller: slotCtrl, decoration: const InputDecoration(labelText: '层级/抽屉', hintText: '如：第二层抽屉', border: OutlineInputBorder())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (selectedZoneId == null || containerCtrl.text.isEmpty || slotCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请填写完整信息')));
                  return;
                }
                try {
                  final result = await _api.post('/space/containers', body: {
                    'zone_id': selectedZoneId,
                    'name': containerCtrl.text,
                    'slots': [{'name': slotCtrl.text, 'level': 1}],
                  });
                  if (result is Map && result['slots'] != null && (result['slots'] as List).isNotEmpty) {
                    setState(() {
                      _selectedSlotId = (result['slots'] as List).first['id'];
                      _selectedSlotName = '$selectedZoneName / ${result['name']} / ${slotCtrl.text}';
                    });
                  }
                  if (mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                }
              },
              child: const Text('确定'),
            ),
          ],
        ),
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
      final response = await _api.uploadFile('/items/upload', _image!, {'slot_id': _selectedSlotId!});
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => RecognitionResultScreen(taskId: data['task_id'], slotId: _selectedSlotId!)),
          );
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $body')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拍照添加物品')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('1. 选择地点', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: _locations.map((l) => ChoiceChip(
                  label: Text(l['name'] ?? ''),
                  selected: _selectedLocationId == l['id'],
                  onSelected: (_) => _pickSlot(l['id']),
                )).toList()),
                if (_locations.isEmpty) const Text('请先在「空间」页创建地点', style: TextStyle(color: Colors.grey)),

                if (_selectedSlotId != null) ...[
                  const SizedBox(height: 16),
                  Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(child: Text('位置: $_selectedSlotName')),
                    IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _pickSlot(_selectedLocationId!)),
                  ]))),
                ],

                const SizedBox(height: 20),
                Text('2. 拍照', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_image != null)
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_image!, height: 250, width: double.infinity, fit: BoxFit.cover))
                else
                  Container(height: 200, decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12), color: Colors.grey.shade100,
                  ), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.camera_alt, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8), const Text('点击下方按钮拍照或选择照片'),
                  ]))),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  FilledButton.tonalIcon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera), label: const Text('拍照')),
                  const SizedBox(width: 16),
                  FilledButton.tonalIcon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('相册')),
                ]),
                const SizedBox(height: 24),
                SizedBox(height: 52, child: FilledButton.icon(
                  onPressed: (_image != null && _selectedSlotId != null && !_uploading) ? _upload : null,
                  icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload),
                  label: Text(_uploading ? '上传中...' : '上传并识别'),
                )),
              ]),
            ),
    );
  }
}
