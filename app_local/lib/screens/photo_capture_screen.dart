import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/space_repository.dart';
import 'image_gallery_screen.dart';
import 'recognition_screen.dart';

class PhotoCaptureScreen extends StatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  State<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends State<PhotoCaptureScreen>
    with SingleTickerProviderStateMixin {
  final _spaceRepo = SpaceRepository();
  List<Map<String, dynamic>> _slots = [];
  String? _selectedSlotId;
  bool _loading = true;
  int _galleryRefresh = 0;
  int _lastRevision = -1;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && !_tabs.indexIsChanging) {
        setState(() => _galleryRefresh++);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = context.watch<AppState>().revision;
    if (rev != _lastRevision) {
      _lastRevision = rev;
      _loadSlots();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    setState(() => _loading = true);
    final locId = context.read<AppState>().activeLocationId;
    final all = <Map<String, dynamic>>[];
    if (locId != null) {
      final zones = await _spaceRepo.listZones(locId);
      for (final z in zones) {
        final containers = await _spaceRepo.listContainers(z['id'] as String);
        for (final c in containers) {
          final slots = await _spaceRepo.listSlots(c['id'] as String);
          for (final s in slots) {
            final bc = await _spaceRepo.breadcrumbForSlot(s['id'] as String);
            all.add({...s, 'breadcrumb': bc});
          }
        }
      }
    }
    _slots = all;
    _selectedSlotId = all.isNotEmpty ? all.first['id'] as String : null;
    setState(() => _loading = false);
  }

  void _goRecognize() {
    if (_selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择存放层级')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecognitionScreen(slotId: _selectedSlotId!),
      ),
    ).then((_) => setState(() => _galleryRefresh++));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('拍照与图库'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.camera_alt), text: '拍照识别'),
            Tab(icon: Icon(Icons.photo_library), text: '原始图片'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('选择物品存放位置', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedSlotId,
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                        items: _slots
                            .map((s) => DropdownMenuItem(
                                  value: s['id'] as String,
                                  child: Text(s['breadcrumb']?.toString() ?? s['name']?.toString() ?? ''),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSlotId = v),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        '流程：拍照 → 上传获 URL → 调用千问 VL 识别 → 确认后存入本地数据库\n'
                        '原图自动保存到应用目录 images/年/月/日/',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _goRecognize,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('开始拍照识别'),
                      ),
                    ],
                  ),
                ),
          ImageGalleryScreen(refreshToken: _galleryRefresh),
        ],
      ),
    );
  }
}
