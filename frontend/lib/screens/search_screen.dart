import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
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
  List<dynamic> _recentItems = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _loading = false;
  bool _loadingRecent = false;
  bool _hasSearched = false;
  String? _error;
  int _loadedListVersion = -1;

  final _suggestions = ['鼠标', '充电', '保暖', '发票', '工具', '药品', '冬季', '相机'];

  @override
  void initState() {
    super.initState();
    _loadedListVersion = context.read<AppState>().searchListVersion;
    _loadRecentItems();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final locId = context.read<AppState>().activeLocationId;
      final path = locId.isNotEmpty
          ? '/search/categories?location_id=$locId'
          : '/search/categories';
      final data = await _api.get(path);
      if (mounted) {
        setState(() {
          _categories = List<String>.from(data['categories'] ?? []);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRecentItems() async {
    setState(() => _loadingRecent = true);
    try {
      final locId = context.read<AppState>().activeLocationId;
      final path = locId.isNotEmpty
          ? '/search/recent?limit=30&location_id=$locId'
          : '/search/recent?limit=30';
      final data = await _api.get(path);
      if (mounted) {
        setState(() {
          _recentItems = (data['results'] as List?) ?? [];
        });
      }
    } catch (_) {
      if (mounted) setState(() => _recentItems = []);
    }
    if (mounted) setState(() => _loadingRecent = false);
  }

  Future<void> _searchByImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920);
    if (picked == null) return;
    setState(() { _loading = true; _error = null; _hasSearched = true; });
    try {
      final locId = context.read<AppState>().activeLocationId;
      final fields = <String, String>{};
      if (locId.isNotEmpty) fields['location_id'] = locId;
      final data = await _api.uploadMultipart('/search/by-image', File(picked.path), fields: fields);
      setState(() { _results = (data['results'] as List?) ?? []; });
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  void _openInSpace(dynamic result) {
    final slotId = result['slot_id']?.toString() ?? '';
    if (slotId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法定位：缺少层级信息')));
      return;
    }
    context.read<AppState>().openSlotInSpace(slotId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已跳转到空间：${result['breadcrumb'] ?? ''}')),
    );
  }

  Future<void> _search(String text) async {
    if (text.isEmpty) return;
    setState(() { _loading = true; _error = null; _hasSearched = true; });
    try {
      final locId = context.read<AppState>().activeLocationId;
      final data = await _api.post('/search/hybrid', body: {
        'text': text,
        'limit': 20,
        if (locId.isNotEmpty) 'location_id': locId,
        if (_selectedCategory != null && _selectedCategory!.isNotEmpty) 'category': _selectedCategory,
      });
      setState(() { _results = (data['results'] as List?) ?? []; });
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final listVersion = context.watch<AppState>().searchListVersion;
    if (listVersion != _loadedListVersion) {
      _loadedListVersion = listVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadRecentItems();
          _loadCategories();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('检索')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _ctrl,
              hintText: '输入物品名称、品牌、或描述（如：保暖穿的）...',
              onSubmitted: _search,
              leading: const Icon(Icons.search),
              trailing: [
                IconButton(icon: const Icon(Icons.image_search), tooltip: '以图搜图', onPressed: _loading ? null : _searchByImage),
                IconButton(icon: const Icon(Icons.refresh), tooltip: '刷新', onPressed: _loadRecentItems),
              ],
            ),
          ),
          if (_categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('全部分类'),
                      selected: _selectedCategory == null,
                      onSelected: (_) {
                        setState(() => _selectedCategory = null);
                        if (_hasSearched && _ctrl.text.isNotEmpty) _search(_ctrl.text);
                      },
                    ),
                    const SizedBox(width: 8),
                    ..._categories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(c),
                        selected: _selectedCategory == c,
                        onSelected: (sel) {
                          setState(() => _selectedCategory = sel ? c : null);
                          if (_hasSearched && _ctrl.text.isNotEmpty) _search(_ctrl.text);
                        },
                      ),
                    )),
                  ],
                ),
              ),
            ),
          // Recent items below search bar
          if (_recentItems.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('已添加的物品', style: Theme.of(context).textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _loadingRecent
                  ? const LinearProgressIndicator()
                  : Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _recentItems.map((r) {
                        final label = r['item_label'] ?? '';
                        final slotId = r['slot_id']?.toString() ?? '';
                        return ActionChip(
                          avatar: const Icon(Icons.inventory_2, size: 18),
                          label: Text(label, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            if (slotId.isNotEmpty) {
                              _openInSpace(r);
                            } else {
                              _ctrl.text = label;
                              _search(label);
                            }
                          },
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 8),
          ],
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
                                  onTap: () => _openInSpace(r),
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
