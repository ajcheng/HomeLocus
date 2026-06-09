import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/item_repository.dart';
import '../services/local_file_service.dart';
import '../services/media_gateway_service.dart';
import '../services/vision_service.dart';
import '../widgets/item_image.dart';

class RecognitionScreen extends StatefulWidget {
  final String slotId;
  const RecognitionScreen({super.key, required this.slotId});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  final _localFiles = LocalFileService();
  final _media = MediaGatewayService();
  final _vision = VisionService();
  final _items = ItemRepository();

  File? _image;
  String? _remoteUrl;
  List<VisionItem> _detected = [];
  final Set<int> _selected = {};
  bool _loading = false;
  String? _error;
  String? _status;

  Future<void> _pickAndRecognize() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1920);
    if (picked == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _detected = [];
      _selected.clear();
      _status = '保存到本机…';
    });

    try {
      final config = context.read<AppState>().config;
      final localPath = await _localFiles.saveImageFromPicker(picked);
      _image = File(localPath);

      setState(() => _status = '上传图片获取 URL…');
      _remoteUrl = await _media.uploadImage(_image!, config);

      setState(() => _status = '调用视觉大模型识别…');
      _detected = await _vision.recognize(_remoteUrl!, config);
      _selected.addAll(List.generate(_detected.length, (i) => i));

      setState(() => _status = '识别完成，请确认入库');
    } catch (e) {
      setState(() => _error = '$e');
    }
    setState(() => _loading = false);
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少选择一项')),
      );
      return;
    }
    for (final i in _selected) {
      final v = _detected[i];
      await _items.insert(
        slotId: widget.slotId,
        label: v.label,
        brand: v.brand,
        category: v.category,
        color: v.color,
        purpose: v.purpose,
        localImagePath: _image?.path,
        remoteImageUrl: _remoteUrl,
        rawRecognition: v.rawText,
      );
    }
    context.read<AppState>().bump();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${_selected.length} 件到本地数据库')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('识别确认')),
      body: _loading
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(_status ?? '处理中…'),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  ),
                if (_image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: ItemImage(
                        localPath: _image!.path,
                        remoteUrl: _remoteUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                if (_detected.isEmpty)
                  FilledButton.icon(
                    onPressed: _pickAndRecognize,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('拍照并识别'),
                  )
                else ...[
                  const Text('识别结果（勾选后存入本地）', style: TextStyle(fontWeight: FontWeight.bold)),
                  for (var i = 0; i < _detected.length; i++)
                    CheckboxListTile(
                      value: _selected.contains(i),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
                      title: Text(_detected[i].label),
                      subtitle: Text([
                        if (_detected[i].brand != null) '品牌: ${_detected[i].brand}',
                        if (_detected[i].color != null) '颜色: ${_detected[i].color}',
                        if (_detected[i].category != null) '分类: ${_detected[i].category}',
                      ].join(' · ')),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _confirm, child: const Text('确认入库')),
                  TextButton(onPressed: _pickAndRecognize, child: const Text('重新拍照')),
                ],
              ],
            ),
    );
  }
}
