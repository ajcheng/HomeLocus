import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/item_repository.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _itemRepo = ItemRepository();
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  List<Map<String, dynamic>> _marks = [];
  String? _selectedTag;
  bool _includeHistory = false;
  bool _loading = false;
  bool _searched = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMarks();
      _search();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _search);
  }

  Future<void> _loadMarks() async {
    _marks = await _itemRepo.listMarkStats(history: _includeHistory);
    if (mounted) setState(() {});
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _searched = true;
      _error = null;
    });
    try {
      _results = await _itemRepo.search(
        text: _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
        tag: _selectedTag,
        includeHistory: _includeHistory,
      );
    } catch (e) {
      _results = [];
      _error = '搜索失败: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _archiveByTag() async {
    if (_selectedTag == null) return;
    final n = await _itemRepo.archiveByTag(_selectedTag!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已归档 $n 件')));
      await _loadMarks();
      await _search();
      context.read<AppState>().bump();
    }
  }

  List<String> _tags(dynamic raw) {
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地检索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('现有')),
                ButtonSegment(value: true, label: Text('历史')),
              ],
              selected: {_includeHistory},
              onSelectionChanged: (s) async {
                setState(() => _includeHistory = s.first);
                await _loadMarks();
                await _search();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SearchBar(
              controller: _ctrl,
              hintText: _includeHistory ? '搜索已归档物品（名称、颜色、语音原文…）' : '搜索物品名称、颜色、分类、语音原文…',
              onSubmitted: (_) => _search(),
              trailing: [
                if (_ctrl.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      _search();
                    },
                  ),
                IconButton(icon: const Icon(Icons.search), onPressed: _search),
              ],
            ),
          ),
          if (_marks.isNotEmpty)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  FilterChip(
                    label: const Text('全部'),
                    selected: _selectedTag == null,
                    onSelected: (_) {
                      setState(() => _selectedTag = null);
                      _search();
                    },
                  ),
                  for (final m in _marks)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: FilterChip(
                        label: Text('${m['tag']} (${m['count']})'),
                        selected: _selectedTag == m['tag'],
                        onSelected: (v) {
                          setState(() => _selectedTag = v ? m['tag'] as String : null);
                          _search();
                        },
                      ),
                    ),
                  if (!_includeHistory && _selectedTag != null)
                    TextButton(onPressed: _archiveByTag, child: Text('完成「$_selectedTag」')),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? const Center(child: Text('输入关键词开始搜索'))
                    : _results.isEmpty
                        ? Center(
                            child: Text(
                              _ctrl.text.trim().isEmpty ? '暂无物品，请先通过拍照或语音添加' : '未找到「${_ctrl.text.trim()}」',
                            ),
                          )
                        : ListView.builder(
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              final tags = _tags(r['tags']);
                              return ListTile(
                                title: Text(r['label']?.toString() ?? ''),
                                subtitle: Text([
                                  r['breadcrumb'] ?? '',
                                  if (r['color'] != null) '颜色: ${r['color']}',
                                  if (tags.isNotEmpty) tags.join('、'),
                                  if (r['raw_recognition'] != null &&
                                      r['raw_recognition'] != r['label'])
                                    '原文: ${r['raw_recognition']}',
                                  if (r['is_deleted'] == 1) '已归档',
                                ].where((e) => e.isNotEmpty).join('\n')),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
