import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';

class VoiceInputScreen extends StatefulWidget {
  final String locationId;
  const VoiceInputScreen({super.key, required this.locationId});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  final _api = ApiClient();
  final _recorder = AudioRecorder();
  final _textCtrl = TextEditingController();
  final _textFocus = FocusNode();
  bool _isRecording = false;
  bool _loading = false;
  bool _recordCompleted = false;
  String? _result;
  String? _error;
  int _recordSeconds = 0;
  Timer? _timer;
  String _statusText = '点击麦克风开始语音输入';
  String? _audioPath;

  bool get _canSubmit => !_loading && _textCtrl.text.trim().isNotEmpty;

  String get _effectiveLocationId {
    if (widget.locationId.isNotEmpty) return widget.locationId;
    return context.read<AppState>().activeLocationId;
  }

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限，请在系统设置中允许')),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    _audioPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    setState(() {
      _isRecording = true;
      _recordCompleted = false;
      _recordSeconds = 0;
      _statusText = '正在录音... 请说出物品信息';
      _error = null;
      _result = null;
    });

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: _audioPath!,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });

    Future.delayed(const Duration(seconds: 30), () {
      if (_isRecording && mounted) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    final audioFile = path ?? _audioPath;

    setState(() {
      _isRecording = false;
      _recordCompleted = true;
      _statusText = '录音完成，$_recordSeconds 秒';
    });

    if (audioFile == null || !File(audioFile).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音失败，请重试或改用文字输入')),
        );
      }
      return;
    }

    await _uploadAudio(File(audioFile));
  }

  Future<void> _uploadAudio(File file) async {
    final locId = _effectiveLocationId;
    if (locId.isEmpty) {
      setState(() => _error = '请先在「空间」页选择地点后再使用语音添加');
      return;
    }

    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final data = await _api.uploadAudio(
        '/speech/add-item',
        file,
        fields: {'location_id': locId},
        timeoutSeconds: 120,
      );
      final transcription = (data['transcription'] ?? '').toString();
      if (transcription.isNotEmpty) {
        _textCtrl.text = transcription;
      }
      await _handleSpeechResponse(data, transcription);
    } catch (e) {
      setState(() => _error = '$e'.split('\n').first);
    }
    setState(() => _loading = false);
  }

  Future<void> _processText(String text) async {
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final data = await _api.post('/speech/add-item-text', body: {
        'text': text,
        'location_id': _effectiveLocationId.isNotEmpty ? _effectiveLocationId : null,
      });
      await _handleSpeechResponse(data, text);
    } catch (e) {
      setState(() => _error = '$e'.split('\n').first);
    }
    setState(() => _loading = false);
  }

  Future<void> _handleSpeechResponse(dynamic data, String fallbackText) async {
    if (data is! Map) return;

    if (data['matched_slot'] != null) {
      final slot = data['matched_slot'];
      final parsed = data['parsed_item'];
      final transcription = (data['transcription'] ?? fallbackText).toString();
      setState(() {
        _result = '识别: $transcription\n物品: ${parsed?['label'] ?? fallbackText}\n位置: ${slot['breadcrumb'] ?? slot['slot_name'] ?? '未知'}';
      });

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('识别结果'),
          content: Text(_result!),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认添加')),
          ],
        ),
      );

      if (confirm == true && parsed != null && slot != null) {
        await _api.post('/speech/add-item/confirm', body: {
          'transcription': transcription,
          'parsed_item': parsed,
          'slot_id': slot['slot_id'],
        });
        if (mounted) {
          context.read<AppState>().refreshSearchItems();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('物品已添加')));
          Navigator.pop(context);
        }
      }
    } else {
      final hint = (data['transcription'] ?? fallbackText).toString();
      if (hint.isNotEmpty && _textCtrl.text.isEmpty) {
        _textCtrl.text = hint;
      }
      setState(() => _error = '未能自动匹配位置。请尝试：\n"房间名+储物柜+层级+物品名"\n如："主卧大衣柜第二层放了鼠标"');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音添加物品')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                GestureDetector(
                  onTap: _loading ? null : _toggleRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isRecording ? Colors.red : Colors.blue,
                      boxShadow: _isRecording
                          ? [BoxShadow(color: Colors.red.withAlpha(80), blurRadius: 20, spreadRadius: 5)]
                          : [BoxShadow(color: Colors.blue.withAlpha(60), blurRadius: 10, spreadRadius: 2)],
                    ),
                    child: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isRecording ? '${_recordSeconds}s' : _statusText,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                    color: _isRecording ? Colors.red : Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_isRecording) ...[
                  const SizedBox(height: 8),
                  Text('再次点击停止并识别', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
                if (_recordCompleted && !_isRecording && !_loading) ...[
                  const SizedBox(height: 8),
                  Text(
                    '录音已上传识别，也可在下方修改文字后重新提交',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: '文字描述（可编辑）',
              hintText: '主卧大衣柜第二层有罗技鼠标和充电宝',
              border: const OutlineInputBorder(),
              helperText: _recordCompleted ? '可修改识别结果后重新提交' : null,
            ),
            enabled: !_loading,
            onSubmitted: _canSubmit ? (v) => _processText(v.trim()) : null,
          ),
          const SizedBox(height: 12),
          Text('示例: 「客厅电视柜左侧抽屉放了充电宝和发票」',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _canSubmit ? () => _processText(_textCtrl.text.trim()) : null,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.psychology),
              label: Text(_loading ? 'AI 解析中...' : '智能识别并添加'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 16),
          if (_result != null)
            Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Text(_result!)))
          else if (_error != null)
            Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Colors.red)))),
        ]),
      ),
    );
  }
}
