import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';

class RecognitionResultScreen extends StatefulWidget {
  final String taskId;
  final String slotId;

  const RecognitionResultScreen({super.key, required this.taskId, required this.slotId});

  @override
  State<RecognitionResultScreen> createState() => _RecognitionResultScreenState();
}

class _RecognitionResultScreenState extends State<RecognitionResultScreen> {
  final _api = ApiClient();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  int _confirmedCount = 0;

  @override
  void initState() {
    super.initState();
    _pollTask();
  }

  Future<void> _pollTask() async {
    // Vision AI can take ~100s; poll up to ~3 minutes
    for (var i = 0; i < 90; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final data = await _api.get('/items/task-status/${widget.taskId}');
        if (data['status'] == 'completed') {
          final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          setState(() { _items = items; _loading = false; });
          return;
        } else if (data['status'] == 'failed') {
          setState(() => _loading = false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('识别失败: ${data['error'] ?? '未知错误'}')),
            );
          }
          return;
        }
      } catch (_) {}
    }
    setState(() => _loading = false);
  }

  Future<void> _confirmItem(int index) async {
    final item = _items[index];
    final ctrl = TextEditingController(text: item['label'] ?? '');
    final chargeCtrl = CheckboxListTile(
      value: item['is_chargeable'] == true,
      title: const Text('需要充电的设备'),
      onChanged: (v) => item['is_chargeable'] = v,
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认物品'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ctrl, decoration: const InputDecoration(labelText: '物品名称')),
            const SizedBox(height: 8),
            Text('品牌: ${item['brand'] ?? '未知'}'),
            Text('分类: ${item['category'] ?? '未分类'}'),
            CheckboxListTile(
              value: item['is_chargeable'] == true,
              title: const Text('需充电设备'),
              onChanged: (v) => setState(() => item['is_chargeable'] = v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              item['label'] = ctrl.text;
              try {
                await _api.put('/items/confirm/${item['id']}', body: {
                  'confirmed_label': ctrl.text,
                  'slot_id': widget.slotId,
                  'bounding_box': item['bounding_box'],
                  'brand': item['brand'],
                  'category': item['category'],
                  'thumbnail_path': item['thumbnail_path'],
                  'confidence': item['confidence'],
                  'is_chargeable_device': item['is_chargeable'] == true,
                  'charge_reminder_cycle_days': 90,
                });
                setState(() => _confirmedCount++);
                if (mounted) context.read<AppState>().refreshSearchItems();
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
              }
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? 'AI 识别中...' : '确认物品 (${_confirmedCount}/${_items.length})'),
      ),
      body: _loading
          ? const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('AI 正在分析照片，请稍候...'),
              ]),
            )
          : _items.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.search_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('未识别到物品'),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => Navigator.pop(context), child: const Text('返回')),
                  ]),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final item = _items[i];
                    final confirmed = item['_confirmed'] == true;
                    return Card(
                      color: confirmed ? Colors.green.shade50 : null,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: item['thumbnail_url'] != null
                            ? Image.network(item['thumbnail_url'], width: 60, height: 60, fit: BoxFit.cover)
                            : const Icon(Icons.image, size: 48),
                        title: Text(item['label'] ?? '未知物品'),
                        subtitle: Text([
                          if (item['brand'] != null) '品牌: ${item['brand']}',
                          if (item['category'] != null) item['category'],
                          '置信度: ${((item['confidence'] ?? 0) * 100).toStringAsFixed(0)}%',
                        ].join(' | ')),
                        trailing: confirmed
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : FilledButton.tonal(
                                onPressed: () => _confirmItem(i),
                                child: const Text('确认'),
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}
