import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/item_media_store.dart';
import '../widgets/item_entry_fields.dart';

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

class _ItemEditors {
  final TextEditingController labelCtrl;
  final TextEditingController brandCtrl;
  final TextEditingController categoryCtrl;
  final TextEditingController colorCtrl;
  bool chargeable;

  _ItemEditors({
    required this.labelCtrl,
    required this.brandCtrl,
    required this.categoryCtrl,
    required this.colorCtrl,
    required this.chargeable,
  });

  factory _ItemEditors.fromItem(Map<String, dynamic> item) => _ItemEditors(
        labelCtrl: TextEditingController(text: item['label']?.toString() ?? ''),
        brandCtrl: TextEditingController(text: item['brand']?.toString() ?? ''),
        categoryCtrl: TextEditingController(text: item['category']?.toString() ?? ''),
        colorCtrl: TextEditingController(text: item['color']?.toString() ?? ''),
        chargeable: item['is_chargeable'] == true,
      );

  void applyTo(Map<String, dynamic> item) {
    item['label'] = labelCtrl.text.trim();
    item['brand'] = brandCtrl.text.trim().isEmpty ? null : brandCtrl.text.trim();
    item['category'] = categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim();
    item['color'] = colorCtrl.text.trim().isEmpty ? null : colorCtrl.text.trim();
    item['is_chargeable'] = chargeable;
  }

  void dispose() {
    labelCtrl.dispose();
    brandCtrl.dispose();
    categoryCtrl.dispose();
    colorCtrl.dispose();
  }
}

class _RecognitionResultScreenState extends State<RecognitionResultScreen> {
  final _api = ApiClient();
  final _mediaStore = ItemMediaStore();
  List<Map<String, dynamic>> _items = [];
  final Map<int, _ItemEditors> _editors = {};
  bool _loading = true;
  bool _submitting = false;

  int get _confirmedCount => _items.where((i) => i['_confirmed'] == true).length;
  int get _pendingCount => _items.length - _confirmedCount;

  @override
  void initState() {
    super.initState();
    _pollTask();
  }

  @override
  void dispose() {
    for (final e in _editors.values) {
      e.dispose();
    }
    super.dispose();
  }

  void _resetEditors() {
    for (final e in _editors.values) {
      e.dispose();
    }
    _editors.clear();
    for (var i = 0; i < _items.length; i++) {
      _editors[i] = _ItemEditors.fromItem(_items[i]);
    }
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
          setState(() {
            _items = items;
            _loading = false;
          });
          _resetEditors();
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

  Future<bool> _confirmOne(int index) async {
    final item = _items[index];
    if (item['_confirmed'] == true) return true;

    final editor = _editors[index];
    if (editor != null) {
      editor.applyTo(item);
    }
    if ((item['label']?.toString() ?? '').trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请填写物品名称')),
        );
      }
      return false;
    }

    try {
      await _api.put('/items/confirm/${item['id']}', body: {
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

  Future<void> _confirmItem(int index) async {
    final item = _items[index];
    if (item['_confirmed'] == true) return;
    final success = await _confirmOne(index);
    if (success && mounted) {
      context.read<AppState>().refreshSearchItems();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已入库：${item['label']}')),
      );
      setState(() {});
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
      for (final i in pending) {
        _editors[i]?.applyTo(_items[i]);
      }
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
                          final editor = _editors[i];
                          return Card(
                            color: confirmed ? Colors.green.shade50 : null,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      if (item['thumbnail_url'] != null)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: Image.network(
                                            item['thumbnail_url'],
                                            width: 56,
                                            height: 56,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.image, size: 40),
                                          ),
                                        )
                                      else
                                        const Icon(Icons.image, size: 40),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          confirmed
                                              ? (item['label'] ?? '未知物品')
                                              : '识别结果 ${i + 1} · 置信度 ${((item['confidence'] ?? 0) * 100).toStringAsFixed(0)}%',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (confirmed)
                                        const Icon(Icons.check_circle, color: Colors.green),
                                    ],
                                  ),
                                  if (!confirmed && editor != null) ...[
                                    const SizedBox(height: 8),
                                    ItemEntryFields(
                                      labelCtrl: editor.labelCtrl,
                                      brandCtrl: editor.brandCtrl,
                                      categoryCtrl: editor.categoryCtrl,
                                      colorCtrl: editor.colorCtrl,
                                      showChargeable: true,
                                      chargeable: editor.chargeable,
                                      onChargeableChanged: (v) => setState(() => editor.chargeable = v),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton.tonal(
                                        onPressed: _submitting ? null : () => _confirmItem(i),
                                        child: const Text('确认入库'),
                                      ),
                                    ),
                                  ],
                                ],
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
