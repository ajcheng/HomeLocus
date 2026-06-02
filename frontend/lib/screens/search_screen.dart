import 'package:flutter/material.dart';
import '../services/api_client.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiClient();
  final _ctrl = TextEditingController();
  List<dynamic> _results = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;

  final _suggestions = ['鼠标', '充电', '保暖', '发票', '工具', '药品', '冬季', '相机'];

  Future<void> _search(String text) async {
    if (text.isEmpty) return;
    setState(() { _loading = true; _error = null; _hasSearched = true; });
    try {
      final data = await _api.post('/search/hybrid', body: {'text': text, 'limit': 20});
      setState(() { _results = (data['results'] as List?) ?? []; });
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('检索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _ctrl,
              hintText: '输入物品名称、品牌、或描述（如：保暖穿的）...',
              onSubmitted: _search,
              leading: const Icon(Icons.search),
              trailing: [
                IconButton(icon: const Icon(Icons.image), tooltip: '以图搜图', onPressed: () {}),
              ],
            ),
          ),
          // Suggestions
          if (!_hasSearched)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _suggestions.map((s) => ActionChip(
                  label: Text(s),
                  onPressed: () { _ctrl.text = s; _search(s); },
                )).toList(),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('搜索中...'),
                  ]))
                : _error != null
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 8),
                        Text('搜索失败: $_error'),
                        const SizedBox(height: 8),
                        FilledButton.tonal(onPressed: () => _search(_ctrl.text), child: const Text('重试')),
                      ]))
                    : _hasSearched && _results.isEmpty
                        ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('未找到匹配物品'),
                          ]))
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Text((r['item_label'] ?? '?')[0], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text(r['item_label'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Expanded(child: Text(r['breadcrumb'] ?? '', style: const TextStyle(fontSize: 13, color: Colors.grey))),
                                      ]),
                                      if (r['score'] != null && r['score'] > 0)
                                        Text('相关度: ${(r['score'] * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: Colors.green)),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
