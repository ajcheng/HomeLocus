import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app/app_state.dart';
import '../services/asr_service.dart';
import '../services/item_repository.dart';
import '../services/local_file_service.dart';
import '../services/space_repository.dart';
import '../utils/voice_parser.dart';

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  final _recorder = AudioRecorder();
  final _asr = AsrService();
  final _items = ItemRepository();
  final _spaceRepo = SpaceRepository();
  final _localFiles = LocalFileService();

  bool _recording = false;
  bool _loading = false;
  String? _text;
  String? _selectedSlotId;
  List<Map<String, dynamic>> _slots = [];
  int _lastRevision = -1;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadSlots() async {
    final locId = context.read<AppState>().activeLocationId;
    final all = <Map<String, dynamic>>[];
    if (locId != null) {
      final zones = await _spaceRepo.listZones(locId);
      for (final z in zones) {
        for (final c in await _spaceRepo.listContainers(z['id'] as String)) {
          for (final s in await _spaceRepo.listSlots(c['id'] as String)) {
            all.add({
              ...s,
              'breadcrumb': await _spaceRepo.breadcrumbForSlot(s['id'] as String),
            });
          }
        }
      }
    }
    setState(() {
      _slots = all;
      _selectedSlotId = all.isNotEmpty ? all.first['id'] as String : null;
    });
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
    final file = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.wav), path: file);
    setState(() => _recording = true);
  }

  Future<void> _transcribe(File audio) async {
    setState(() {
      _loading = true;
      _text = null;
    });
    try {
      final config = context.read<AppState>().config;
      await _localFiles.saveAudio(audio);
      _text = await _asr.transcribe(audio, config);
    } catch (e) {
      _text = '识别失败: $e';
    }
    setState(() => _loading = false);
  }

  Future<void> _saveAsItem() async {
    if (_text == null || _text!.trim().isEmpty || _selectedSlotId == null) return;
    final parsed = parseVoiceText(_text!);
    await _items.insert(
      slotId: _selectedSlotId!,
      label: parsed.label,
      color: parsed.color,
      tags: parsed.tags,
      rawRecognition: _text,
    );
    context.read<AppState>().bump();
    if (mounted) {
      final hint = [
        parsed.label,
        if (parsed.color != null) parsed.color,
      ].join(' · ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加: $hint')));
      setState(() => _text = null);
    }
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
                label: Text(_recording ? '停止录音' : '按住说话（点击开始/停止）'),
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
              '流程：录音 → 上传 ASR 网关 → Qwen3-ASR 转文字 → 存入本地',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
