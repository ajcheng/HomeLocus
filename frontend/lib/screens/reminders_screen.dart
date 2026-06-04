import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _api = ApiClient();
  List<dynamic> _reminders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final locId = context.read<AppState>().activeLocationId;
      final path = locId.isNotEmpty
          ? '/reminders/pending?location_id=$locId'
          : '/reminders/pending';
      final data = await _api.get(path);
      setState(() { _reminders = data is List ? data : []; });
    } catch (_) {}
    setState(() => _loading = false);
  }

  Future<void> _completeCharge(String itemId) async {
    try {
      await _api.post('/reminders/charge/complete', body: {'item_id': itemId, 'next_reminder_days': 90});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _markReturned(String itemId) async {
    try {
      await _api.post('/reminders/borrow/return', body: {'item_id': itemId});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openItemLocation(dynamic r) {
    final slotId = r['slot_id']?.toString() ?? '';
    if (slotId.isEmpty) return;
    context.read<AppState>().openSlotInSpace(slotId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已跳转到：${r['breadcrumb'] ?? ''}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? const Center(child: Text('暂无待处理提醒'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: _reminders.length,
                    itemBuilder: (_, i) {
                      final r = _reminders[i];
                      final isCharge = r['reminder_type'] == 'charge';
                      final notifyCount = r['notify_count'] ?? 0;
                      final label = r['item_label'] ?? r['item_id'] ?? '';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          onTap: () => _openItemLocation(r),
                          leading: Icon(
                            isCharge ? Icons.battery_charging_full : Icons.assignment_return,
                            color: isCharge ? Colors.orange : Colors.purple,
                          ),
                          title: Text(
                            isCharge ? '充电提醒 · $label' : '借出归位 · $label',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (r['breadcrumb'] != null)
                                Text(r['breadcrumb'], style: const TextStyle(fontSize: 12)),
                              if (r['notes'] != null && (r['notes'] as String).isNotEmpty)
                                Text(r['notes'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              if (notifyCount > 0)
                                Text(
                                  '已提醒 $notifyCount 次，未处理将每 24 小时再提醒',
                                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
                                ),
                            ],
                          ),
                          isThreeLine: true,
                          trailing: FilledButton.tonal(
                            onPressed: () => isCharge ? _completeCharge(r['item_id']) : _markReturned(r['item_id']),
                            child: Text(isCharge ? '已充电' : '已归位'),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
