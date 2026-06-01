import 'package:flutter/material.dart';
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
      final data = await _api.get('/reminders/pending');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提醒'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? const Center(child: Text('暂无待处理提醒'))
              : ListView.builder(
                  itemCount: _reminders.length,
                  itemBuilder: (_, i) {
                    final r = _reminders[i];
                    final isCharge = r['reminder_type'] == 'charge';
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: Icon(isCharge ? Icons.battery_charging_full : Icons.assignment_return, color: isCharge ? Colors.orange : Colors.purple),
                        title: Text(isCharge ? '充电提醒' : '借出归位提醒'),
                        subtitle: Text('${r['notes'] ?? ''}\n下次提醒: ${r['next_remind_at'] ?? ''}'),
                        trailing: FilledButton.tonal(
                          onPressed: () => isCharge ? _completeCharge(r['item_id']) : _markReturned(r['item_id']),
                          child: Text(isCharge ? '已充电' : '已归位'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
