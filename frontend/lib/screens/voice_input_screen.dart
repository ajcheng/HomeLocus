import 'package:flutter/material.dart';
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
  bool _loading = false;
  String? _result;
  String? _error;

  Future<void> _submitVoice() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请输入或语音输入物品描述');
      return;
    }

    setState(() { _loading = true; _error = null; _result = null; });
    try {
      // Use the speech API to parse natural language
      // Since audio recording needs platform plugins, we use text input as fallback
      // The speech endpoint can accept text directly for NLP parsing
      final data = await _api.post('/speech/add-item-text', body: {
        'text': text,
        'location_id': widget.locationId.isNotEmpty ? widget.locationId : null,
      });

      if (data['matched_slot'] != null) {
        final slot = data['matched_slot'];
        setState(() {
          _result = '物品: ${data['parsed_item']?['label'] ?? text}\n'
              '位置: ${slot['breadcrumb'] ?? slot['slot_name'] ?? '未知'}';
        });

        // Auto-confirm if high confidence
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

        if (confirm == true && data['parsed_item'] != null && data['matched_slot'] != null) {
          await _api.post('/speech/add-item/confirm', body: {
            'transcription': text,
            'parsed_item': data['parsed_item'],
            'slot_id': data['matched_slot']['slot_id'],
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('物品已添加')));
            Navigator.pop(context);
          }
        }
      } else {
        setState(() => _error = '未能识别物品和位置，请再试一次');
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
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                const Icon(Icons.mic, size: 56, color: Colors.blue),
                const SizedBox(height: 12),
                const Text('说出物品信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('例如：「主卧大衣柜第二层放了罗技鼠标」', style: TextStyle(color: Colors.grey)),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '物品描述',
              hintText: '大衣柜第二层有罗技鼠标和充电宝',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.text_fields),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submitVoice,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_loading ? '识别中...' : '识别并添加'),
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
