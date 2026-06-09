import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/item_media_store.dart';
import '../services/media_gateway_service.dart';
import '../services/vision_service.dart';
import '../widgets/item_image.dart';

/// 使用本机自定义网关配置进行图像识别（与单机版流程一致）
class ClientRecognitionScreen extends StatefulWidget {
  final String slotId;
  final String localImagePath;

  const ClientRecognitionScreen({
    super.key,
    required this.slotId,
    required this.localImagePath,
  });

  @override
  State<ClientRecognitionScreen> createState() => _ClientRecognitionScreenState();
}

class _ClientRecognitionScreenState extends State<ClientRecognitionScreen> {
  final _api = ApiClient();
  final _media = MediaGatewayService();
  final _vision = VisionService();
  final _mediaStore = ItemMediaStore();

  String? _remoteUrl;
  List<VisionItem> _detected = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  Future<void> _recognize() async {
    setState(() {
      _loading = true;
      _error = null;
      _detected = [];
      _selected.clear();
      _status = '上传图片获取 URL…';
    });
    try {
      final config = context.read<AppState>().settings.recognition;
      final image = File(widget.localImagePath);
      _remoteUrl = await _media.uploadImage(image, config);

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
    setState(() => _saving = true);
    var saved = 0;
    try {
      for (final i in _selected) {
        final v = _detected[i];
        final data = await _api.post('/items/manual', body: {
          'slot_id': widget.slotId,
          'label': v.label,
          'brand': v.brand,
          'category': v.category,
          'color': v.color,
          'purpose': v.purpose,
          'raw_recognition': v.rawText,
        });
        final itemId = data is Map ? data['id']?.toString() : null;
        if (itemId != null) {
          await _mediaStore.link(itemId: itemId, imagePath: widget.localImagePath);
        }
        saved++;
      }
      if (mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已保存 $saved 件到云端')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义识别确认')),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_status ?? '处理中…'),
                ],
              ),
            )
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: ItemImage(
                      localPath: widget.localImagePath,
                      remoteUrl: _remoteUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_detected.isEmpty)
                  FilledButton.icon(
                    onPressed: _recognize,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新识别'),
                  )
                else ...[
                  const Text('识别结果（勾选后存入云端）', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  FilledButton(
                    onPressed: _saving ? null : _confirm,
                    child: Text(_saving ? '保存中…' : '确认入库'),
                  ),
                  TextButton(onPressed: _recognize, child: const Text('重新识别')),
                ],
              ],
            ),
    );
  }
}
