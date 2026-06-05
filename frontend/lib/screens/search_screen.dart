import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/tts_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiClient();
  final _ctrl = TextEditingController();
  final _speech = SpeechToText();
  final _tts = TtsService();

  List<dynamic> _results = [];
  List<dynamic> _recentItems = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _loading = false;
  bool _loadingRecent = false;
  bool _isListening = false;
  bool _speechReady = false;
  bool _hasSearched = false;
  String? _error;
  int _loadedListVersion = -1;
  String _voicePartial = '';

  final _suggestions = ['鼠标', '充电', '保暖', '发票', '工具', '药品', '冬季', '相机'];

  @override
  void initState() {
    super.initState();
    _loadedListVersion = context.read<AppState>().searchListVersion;
    _loadRecentItems();
    _loadCategories();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _speechReady = await _speech.initialize(
      onError: (e) => debugPrint('speech error: $e'),
      onStatus: (s) => debugPrint('speech status: $s'),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _ctrl.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speakWithFeedback(String text) async {
    final ok = await _tts.speak(text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tts.lastError != null
                ? '语音播报失败，请检查系统是否已安装中文语音引擎'
                : '语音播报失败',
          ),
        ),
      );
    }
  }

  Future<void> _speakResults(List<dynamic> results, {String? query}) async {
    final ok = await _tts.speakSearchResults(results, query: query);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法播报：请在系统设置中启用文字转语音（TTS）中文引擎')),
      );
    }
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
      final results = (data['results'] as List?) ?? [];
      if (!mounted) return;
      setState(() => _results = results);
      await _speakResults(results, query: '图片中的物品');
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleVoiceSearch() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    if (!_speechReady) {
      await _initSpeech();
    }
    if (!_speechReady) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本机语音识别不可用，请检查麦克风权限与 Google 语音服务')),
        );
      }
      return;
    }
    setState(() {
      _isListening = true;
      _voicePartial = '';
    });
    final locales = await _speech.locales();
    final zhMatches = locales.where((l) => l.localeId.toLowerCase().startsWith('zh')).toList();
    final zhLocale = zhMatches.isNotEmpty ? zhMatches.first : (locales.isNotEmpty ? locales.first : null);
    await _speech.listen(
      localeId: zhLocale?.localeId,
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 2),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _voicePartial = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          _ctrl.text = r.recognizedWords.trim();
          _search(r.recognizedWords.trim(), speakAfter: true);
          setState(() => _isListening = false);
        }
      },
      onSoundLevelChange: null,
      cancelOnError: true,
    );
  }

  Future<void> _deleteRecentItem(dynamic r) async {
    final id = r['id']?.toString() ?? '';
    final label = r['item_label'] ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除物品'),
        content: Text('确定删除「$label」？将从搜索与空间中移除，不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.delete('/items/$id');
      context.read<AppState>().refreshSearchItems();
      await _loadRecentItems();
      if (_ctrl.text == label) {
        setState(() { _results = []; _hasSearched = false; });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 $label')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openInSpace(dynamic result) {
    final slotId = result['slot_id']?.toString() ?? '';
    if (slotId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法定位：缺少层级信息')),
      );
      return;
    }
    context.read<AppState>().openSlotInSpace(slotId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已跳转到：${result['breadcrumb'] ?? ''}')),
    );
  }

  void _showResultDetail(dynamic r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r['item_label'] ?? r['label'] ?? '',
              style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r['breadcrumb'] ?? '位置未知',
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ),
              ],
            ),
            if (r['score'] != null && (r['score'] as num) > 0) ...[
              const SizedBox(height: 8),
              Text(
                '相关度: ${((r['score'] as num) * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.green.shade700),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _speakWithFeedback(
                        '${r['item_label'] ?? ''}，放在${r['breadcrumb'] ?? ''}',
                      );
                    },
                    icon: const Icon(Icons.volume_up),
                    label: const Text('朗读'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openInSpace(r);
                    },
                    icon: const Icon(Icons.my_location),
                    label: const Text('查看位置'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteRecentItem(r);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text('删除此物品', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _search(String text, {bool speakAfter = false}) async {
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
      if (speakAfter) {
        await _speakResults(_results, query: text);
      }
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  Future<void> _speakCurrentResults() async {
    if (_results.isEmpty) {
      await _speakWithFeedback('当前没有搜索结果');
      return;
    }
    await _speakResults(_results, query: _ctrl.text.trim());
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
      appBar: AppBar(
        title: const Text('检索'),
        actions: [
          if (_hasSearched && _results.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.volume_up),
              tooltip: '朗读搜索结果',
              onPressed: _loading ? null : _speakCurrentResults,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _ctrl,
              hintText: _isListening ? (_voicePartial.isNotEmpty ? _voicePartial : '正在听您说…') : '输入或语音说出要找的物品…',
              onSubmitted: (t) => _search(t),
              leading: Icon(
                _isListening ? Icons.mic : Icons.search,
                color: _isListening ? Colors.red : null,
              ),
              trailing: [
                IconButton(
                  icon: Icon(_isListening ? Icons.stop_circle : Icons.mic_none),
                  tooltip: _isListening ? '停止语音' : '本机语音搜索',
                  color: _isListening ? Colors.red : null,
                  onPressed: _loading ? null : _toggleVoiceSearch,
                ),
                IconButton(
                  icon: const Icon(Icons.image_search),
                  tooltip: '以图搜图',
                  onPressed: _loading ? null : _searchByImage,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '刷新',
                  onPressed: _loadRecentItems,
                ),
              ],
            ),
          ),
          if (_isListening)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '正在本机识别语音（无需联网），说完自动搜索；点击红色按钮停止',
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
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
          if (_recentItems.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('已添加的物品（点击搜索，长按删除）', style: Theme.of(context).textTheme.titleSmall),
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
                        return GestureDetector(
                          onLongPress: () => _deleteRecentItem(r),
                          child: ActionChip(
                            avatar: const Icon(Icons.inventory_2, size: 18),
                            label: Text(label, overflow: TextOverflow.ellipsis),
                            onPressed: () {
                              _ctrl.text = label;
                              _search(label);
                            },
                          ),
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
                      onPressed: () {
                        _ctrl.text = s;
                        _search(s);
                      },
                    )).toList(),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('搜索中...'),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 8),
                            Text('搜索失败: $_error'),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: () => _search(_ctrl.text),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : _hasSearched && _results.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('未找到匹配物品'),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 80),
                            itemCount: _results.length,
                            itemBuilder: (_, i) {
                              final r = _results[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: ListTile(
                                  onTap: () => _showResultDetail(r),
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    child: Text(
                                      (r['item_label'] ?? '?')[0],
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(
                                    r['item_label'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              r['breadcrumb'] ?? '',
                                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (r['score'] != null && r['score'] > 0)
                                        Text(
                                          '相关度: ${(r['score'] * 100).toStringAsFixed(0)}% · 点击查看详情',
                                          style: const TextStyle(fontSize: 11, color: Colors.green),
                                        ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
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
