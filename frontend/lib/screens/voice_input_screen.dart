import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';

class VoiceInputScreen extends StatefulWidget {
  final String locationId;

  const VoiceInputScreen({super.key, required this.locationId});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  bool _isRecording = false;
  String _statusText = '点击按钮开始语音输入';
  String _transcription = '';
  Map<String, dynamic>? _result;
  bool _loading = false;

  final _api = ApiClient();

  Future<void> _toggleRecording() async {
    setState(() {
      _isRecording = !_isRecording;
      _statusText = _isRecording ? '正在录音... 再次点击停止' : '录音已停止';
    });
    // TODO: Integrate with actual audio recording plugin
    // For now simulate with uploaded audio file
  }

  Future<void> _processVoice() async {
    setState(() { _loading = true; _statusText = '正在识别...'; });

    try {
      // TODO: Send audio file via multipart/form-data
      // final response = await _api.postMultipart('/speech/add-item', ...);
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _transcription = '主卧大衣柜第二层放了罗技MX Master 3鼠标';
        _result = {
          'parsed_item': {
            'label': '罗技MX Master 3鼠标',
            'brand': '罗技',
            'category': '电子产品',
            'slot_name_hint': '第二层',
            'container_name_hint': '大衣柜',
            'zone_name_hint': '主卧',
          },
          'matched_slot': {
            'slot_name': '第二层抽屉',
            'container_name': '大衣柜',
            'zone_name': '主卧',
            'location_name': '我的家',
            'breadcrumb': '我的家 / 主卧 / 大衣柜 / 第二层抽屉',
          },
          'needs_confirmation': true,
        };
        _statusText = '识别完成，请确认';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _statusText = '识别失败: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('语音添加物品')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Status area
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      size: 64,
                      color: _isRecording ? Colors.red : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(_statusText, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Record button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(_isRecording ? '停止录音' : '开始录音'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
                const SizedBox(width: 16),
                if (!_isRecording && _transcription.isEmpty)
                  ElevatedButton.icon(
                    onPressed: _loading ? null : _processVoice,
                    icon: _loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                    label: const Text('模拟识别'),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Result
            if (_result != null) ...[
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('识别文字: "$_transcription"'),
                      const SizedBox(height: 8),
                      Text('物品: ${_result!['parsed_item']['label']}'),
                      if (_result!['parsed_item']['brand'] != null)
                        Text('品牌: ${_result!['parsed_item']['brand']}'),
                      const Divider(),
                      Text('匹配位置: ${_result!['matched_slot']['breadcrumb']}'),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                          FilledButton(
                            onPressed: () {
                              // TODO: Call confirm API
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('物品已添加')),
                              );
                              Navigator.pop(context);
                            },
                            child: const Text('确认添加'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
