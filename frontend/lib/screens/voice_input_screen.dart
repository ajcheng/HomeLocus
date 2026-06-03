import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
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

  bool get _canSubmit =>
      !_loading && _textCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      _timer?.cancel();
      setState(() {
        _isRecording = false;
        _recordCompleted = true;
        _statusText = '录音完成，$_recordSeconds 秒';
      });

      if (_textCtrl.text.trim().isNotEmpty) {
        await _processText(_textCtrl.text.trim());
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('录音已结束。请在下方输入物品描述（如：主卧大衣柜第二层放了鼠标），再点「智能识别并添加」'),
            duration: Duration(seconds: 4),
          ),
        );
        _textFocus.requestFocus();
      }
    } else {
      setState(() {
        _isRecording = true;
        _recordCompleted = false;
        _recordSeconds = 0;
        _statusText = '正在录音... 请说出物品信息';
        _error = null;
        _result = null;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _recordSeconds++);
      });

      Future.delayed(const Duration(seconds: 10), () {
        if (_isRecording && mounted) {
          _toggleRecording();
        }
      });
    }
  }

  Future<void> _processText(String text) async {
    setState(() { _loading = true; _error = null; _result = null; });
    try {
      final data = await _api.post('/speech/add-item-text', body: {
        'text': text,
        'location_id': widget.locationId.isNotEmpty ? widget.locationId : null,
      });

      if (data is Map && data['matched_slot'] != null) {
        final slot = data['matched_slot'];
        final parsed = data['parsed_item'];
        setState(() {
          _result = '物品: ${parsed?['label'] ?? text}\n位置: ${slot['breadcrumb'] ?? slot['slot_name'] ?? '未知'}';
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
            'transcription': text,
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
        setState(() => _error = '未能自动匹配位置。请尝试：\n"房间名+储物柜+层级+物品名"\n如："主卧大衣柜第二层放了鼠标"');
      }
    } catch (e) {
      setState(() => _error = '$e'.split('\n').first);
    }
    setState(() => _loading = false);
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
                  Text('点击麦克风停止录音', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                ],
                if (_recordCompleted && !_isRecording) ...[
                  const SizedBox(height: 8),
                  Text(
                    '当前为模拟录音，请在下方文字框输入描述',
                    style: TextStyle(color: Colors.orange.shade700, fontSize: 12),
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
              labelText: '输入物品描述（必填）',
              hintText: '主卧大衣柜第二层有罗技鼠标和充电宝',
              border: const OutlineInputBorder(),
              helperText: _recordCompleted ? '输入后即可点击「智能识别并添加」' : null,
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
