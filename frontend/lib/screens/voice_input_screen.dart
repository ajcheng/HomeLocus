import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/asr_service.dart';
import '../services/item_media_store.dart';
import '../services/local_file_service.dart';
import '../utils/voice_parser.dart';

class VoiceInputScreen extends StatefulWidget {
  final String locationId;
  const VoiceInputScreen({super.key, required this.locationId});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  final _api = ApiClient();
  final _asr = AsrService();
  final _recorder = AudioRecorder();
  final _localFiles = LocalFileService();
  final _mediaStore = ItemMediaStore();

  bool _recording = false;
  bool _loading = false;
  String? _text;
  String? _lastAudioPath;
  String? _selectedSlotId;
  List<Map<String, dynamic>> _slots = [];

  String get _effectiveLocationId {
    if (widget.locationId.isNotEmpty) return widget.locationId;
    return context.read<AppState>().activeLocationId;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSlots());
  }

  Future<void> _loadSlots() async {
    final locId = _effectiveLocationId;
    if (locId.isEmpty) return;
    final all = <Map<String, dynamic>>[];
    try {
      final zones = await _api.get('/space/zones?location_id=$locId') as List;
      for (final z in zones) {
        final containers = await _api.get('/space/containers?zone_id=${z['id']}') as List;
        for (final c in containers) {
          final slots = (c['slots'] as List?) ?? [];
          for (final s in slots) {
            all.add({
              'id': s['id'],
              'breadcrumb': '${z['name']} / ${c['name']} / ${s['name']}',
            });
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _slots = all;
        _selectedSlotId = all.isNotEmpty ? all.first['id'] as String : null;
      });
    }
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final path = await _recorder.stop();
      setState(() => _recording = false);
      if (path == null) return;
      await _transcribe(File(path));
      return;
    }
    if (!await _recorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要麦克风权限')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000), path: file);
    setState(() => _recording = true);
  }

  Future<void> _transcribe(File audio) async {
    setState(() {
      _loading = true;
      _text = null;
    });
    try {
      _lastAudioPath = await _localFiles.saveAudio(audio);
      final appState = context.read<AppState>();
      if (appState.useCustomRecognition) {
        _text = await _asr.transcribe(audio, appState.settings.recognition);
      } else {
        final data = await _api.uploadAudio('/speech/transcribe', audio);
        _text = (data is Map ? data['text'] : null)?.toString();
      }
      if (_text == null || _text!.trim().isEmpty) {
        _text = '识别失败：未返回文字';
      }
    } catch (e) {
      _text = '识别失败: $e';
    }
    setState(() => _loading = false);
  }

  Future<void> _saveAsItem() async {
    if (_text == null || _text!.trim().isEmpty || _selectedSlotId == null) return;
    final parsed = parseVoiceText(_text!);
    setState(() => _loading = true);
    try {
      final data = await _api.post('/speech/save-item', body: {
        'slot_id': _selectedSlotId,
        'text': _text,
        'label': parsed.label,
        'color': parsed.color,
        'tags': parsed.tags,
      });
      final itemId = data is Map ? data['item_id']?.toString() : null;
      if (itemId != null && _lastAudioPath != null) {
        await _mediaStore.link(itemId: itemId, audioPath: _lastAudioPath);
      }
      if (mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已添加: ${parsed.label}${parsed.color != null ? '（${parsed.color}）' : ''}')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音添加')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedSlotId,
              decoration: const InputDecoration(labelText: '存放位置', border: OutlineInputBorder()),
              items: _slots
                  .map((s) => DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(s['breadcrumb']?.toString() ?? ''),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSlotId = v),
            ),
            const SizedBox(height: 24),
            Center(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _recording ? Colors.red : null,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: _loading ? null : _toggleRecord,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_recording ? '停止录音' : '点击开始/停止录音'),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            if (_text != null) ...[
              const Text('识别结果', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(_text!))),
              const SizedBox(height: 8),
              Builder(
                builder: (_) {
                  final p = parseVoiceText(_text!);
                  return Text(
                    '将保存为：${p.label}${p.color != null ? '（${p.color}）' : ''}',
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  );
                },
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: _saveAsItem, child: const Text('保存为物品')),
            ],
            const Spacer(),
            Text(
              context.watch<AppState>().useCustomRecognition
                  ? '流程：录音 → 自定义 ASR 网关 → 解析物品名/颜色 → 存入云端'
                  : '流程：录音 → 服务端 ASR 网关 → 解析物品名/颜色 → 存入云端',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
