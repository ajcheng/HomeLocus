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

  Future<void> _search(String text) async {
    if (text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final data = await _api.post('/search/hybrid', body: {'text': text, 'limit': 20});
      setState(() { _results = (data['results'] as List?) ?? []; });
    } catch (_) {}
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
              hintText: '输入物品名称、品牌、或描述...',
              onSubmitted: _search,
              leading: const Icon(Icons.search),
              trailing: [IconButton(icon: const Icon(Icons.image), onPressed: () {})],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('输入关键词搜索物品'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: const Icon(Icons.image),
                              title: Text(r['item_label'] ?? ''),
                              subtitle: Text('位置: ${r['breadcrumb'] ?? ''}'),
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
