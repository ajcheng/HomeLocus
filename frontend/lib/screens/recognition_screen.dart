import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/item_media_store.dart';

class RecognitionResultScreen extends StatefulWidget {
  final String taskId;
  final String slotId;
  final String? localImagePath;

  const RecognitionResultScreen({
    super.key,
    required this.taskId,
    required this.slotId,
    this.localImagePath,
  });

  @override
  State<RecognitionResultScreen> createState() => _RecognitionResultScreenState();
}

class _RecognitionResultScreenState extends State<RecognitionResultScreen> {
  final _api = ApiClient();
  final _mediaStore = ItemMediaStore();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _submitting = false;

  int get _confirmedCount => _items.where((i) => i['_confirmed'] == true).length;
  int get _pendingCount => _items.length - _confirmedCount;

  @override
  void initState() {
    super.initState();
    _pollTask();
  }

  Future<void> _pollTask() async {
    for (var i = 0; i < 90; i++) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final data = await _api.get('/items/task-status/${widget.taskId}');
        if (data['status'] == 'completed') {
          final items = (data['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          for (final it in items) {
            it['_confirmed'] = false;
          }
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

  Map<String, dynamic> _confirmBody(Map<String, dynamic> item) => {
        'item_id': item['id'],
        'confirmed_label': item['label'] ?? '',
        'slot_id': widget.slotId,
        'bounding_box': item['bounding_box'],
        'brand': item['brand'],
        'category': item['category'],
        'color': item['color'],
        'purpose': item['purpose'],
        'raw_recognition': item['ai_label_raw'] ?? item['label'],
        'thumbnail_path': item['thumbnail_path'],
        'confidence': item['confidence'],
        'is_chargeable_device': item['is_chargeable'] == true,
        'charge_reminder_cycle_days': 90,
      };

  Future<bool> _confirmOne(int index, {String? labelOverride}) async {
    final item = _items[index];
    if (item['_confirmed'] == true) return true;

    if (labelOverride != null) {
      item['label'] = labelOverride;
    }

    try {
      await _api.put('/items/confirm/${item['id']}', body: {
        'confirmed_label': item['label'] ?? '',
        'slot_id': widget.slotId,
        'bounding_box': item['bounding_box'],
        'brand': item['brand'],
        'category': item['category'],
        'thumbnail_path': item['thumbnail_path'],
        'confidence': item['confidence'],
        'is_chargeable_device': item['is_chargeable'] == true,
        'charge_reminder_cycle_days': 90,
      });
      final itemId = item['id']?.toString();
      if (itemId != null && widget.localImagePath != null) {
        await _mediaStore.link(itemId: itemId, imagePath: widget.localImagePath);
      }
      setState(() => item['_confirmed'] = true);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('入库失败: $e')));
      }
      return false;
    }
  }

  Future<void> _confirmItemDialog(int index) async {
    final item = _items[index];
    if (item['_confirmed'] == true) return;

    final ctrl = TextEditingController(text: item['label']?.toString() ?? '');
    var chargeable = item['is_chargeable'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('确认入库'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: '物品名称'),
              ),
              const SizedBox(height: 8),
              if (item['brand'] != null) Text('品牌: ${item['brand']}'),
              if (item['category'] != null) Text('分类: ${item['category']}'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: chargeable,
                title: const Text('需充电设备'),
                onChanged: (v) => setDialog(() {
                  chargeable = v ?? false;
                  item['is_chargeable'] = chargeable;
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认入库'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      item['is_chargeable'] = chargeable;
      final success = await _confirmOne(index, labelOverride: ctrl.text.trim());
      if (success && mounted) {
        context.read<AppState>().refreshSearchItems();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已入库：${ctrl.text.trim()}')),
        );
      }
    }
  }

  Future<void> _confirmAllPending() async {
    final pending = <int>[];
    for (var i = 0; i < _items.length; i++) {
      if (_items[i]['_confirmed'] != true) pending.add(i);
    }
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有待确认的物品')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部入库'),
        content: Text('将把 ${pending.length} 个未确认物品全部入库，是否继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('全部入库')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    var success = 0;
    try {
      final batchItems = pending.map((i) => _confirmBody(_items[i])).toList();
      final result = await _api.post('/items/confirm-batch', body: {
        'slot_id': widget.slotId,
        'items': batchItems,
      });
      if (result is List) {
        success = result.length;
        for (final i in pending) {
          _items[i]['_confirmed'] = true;
          final itemId = _items[i]['id']?.toString();
          if (itemId != null && widget.localImagePath != null) {
            await _mediaStore.link(itemId: itemId, imagePath: widget.localImagePath);
          }
        }
      }
    } catch (_) {
      for (final i in pending) {
        if (await _confirmOne(i)) success++;
      }
    }
    if (mounted) {
      context.read<AppState>().refreshSearchItems();
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已入库 $success 件，未确认的 ${_items.length - _confirmedCount} 件不会添加')),
      );
    }
  }

  void _finish() {
    final skipped = _pendingCount;
    Navigator.pop(context);
    if (skipped > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已入库 $_confirmedCount 件，$skipped 件未确认未入库')),
      );
    } else if (_confirmedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已完成，共入库 $_confirmedCount 件')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_loading ? 'AI 识别中...' : '确认入库 ($_confirmedCount/${_items.length})'),
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
              : Column(
                  children: [
                    if (_pendingCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Text(
                          '请逐项确认；未点确认的物品不会入库',
                          style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
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
                                  ? Image.network(
                                      item['thumbnail_url'],
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(Icons.image, size: 48),
                                    )
                                  : const Icon(Icons.image, size: 48),
                              title: Text(
                                item['label'] ?? '未知物品',
                                style: TextStyle(
                                  decoration: confirmed ? null : TextDecoration.none,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text([
                                if (item['brand'] != null) '品牌: ${item['brand']}',
                                if (item['category'] != null) item['category'],
                                '置信度: ${((item['confidence'] ?? 0) * 100).toStringAsFixed(0)}%',
                                if (confirmed) '✓ 已入库',
                              ].join(' | ')),
                              trailing: confirmed
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : FilledButton.tonal(
                                      onPressed: _submitting ? null : () => _confirmItemDialog(i),
                                      child: const Text('确认'),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _submitting ? null : _finish,
                                child: Text(_pendingCount > 0 ? '完成（跳过未确认）' : '完成'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: (_submitting || _pendingCount == 0)
                                    ? null
                                    : _confirmAllPending,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.done_all),
                                label: Text(_submitting ? '入库中...' : '全部入库 ($_pendingCount)'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
