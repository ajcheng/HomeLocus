import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

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
  final _recorder = AudioRecorder();
  final _tts = TtsService();

  List<dynamic> _results = [];
  List<dynamic> _recentItems = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _loading = false;
  bool _loadingRecent = false;
  bool _isRecording = false;
  bool _hasSearched = false;
  String? _error;
  int _loadedListVersion = -1;
  Timer? _recordTimer;
  int _recordSeconds = 0;

  final _suggestions = ['鼠标', '充电', '保暖', '发票', '工具', '药品', '冬季', '相机'];

  @override
  void initState() {
    super.initState();
    _loadedListVersion = context.read<AppState>().searchListVersion;
    _loadRecentItems();
    _loadCategories();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _ctrl.dispose();
    _tts.stop();
    super.dispose();
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
      await _tts.speakSearchResults(_results, query: '图片中的物品');
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  Future<void> _toggleVoiceSearch() async {
    if (_isRecording) {
      await _stopVoiceSearch();
    } else {
      await _startVoiceSearch();
    }
  }

  Future<void> _startVoiceSearch() async {
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能语音搜索')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/search_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
      path: path,
    );
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordSeconds++);
    });
    Future.delayed(const Duration(seconds: 15), () {
      if (_isRecording && mounted) _stopVoiceSearch(expectedPath: path);
    });
  }

  Future<void> _stopVoiceSearch({String? expectedPath}) async {
    _recordTimer?.cancel();
    final path = await _recorder.stop() ?? expectedPath;
    setState(() => _isRecording = false);
    if (path == null || !File(path).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('录音失败，请重试')),
        );
      }
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _api.uploadAudio('/speech/transcribe', File(path), timeoutSeconds: 60);
      final text = (data['text'] ?? '').toString().trim();
      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未识别到语音，请再说一次')),
          );
        }
      } else {
        _ctrl.text = text;
        await _search(text, speakAfter: true);
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
    if (mounted) setState(() => _loading = false);
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
                      _tts.speak(
                        '${r['item_label'] ?? ''}，放在${r['breadcrumb'] ?? ''}',
                      );
                    },
                    icon: const Icon(Icons.volume_up),
                    label: const Text('朗读'),
                  ),
                ),
                const SizedBox(width: 12),
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
        await _tts.speakSearchResults(_results, query: text);
      }
    } catch (e) {
      setState(() { _error = '$e'; _results = []; });
    }
    setState(() => _loading = false);
  }

  Future<void> _speakCurrentResults() async {
    if (_results.isEmpty) {
      await _tts.speak('当前没有搜索结果');
      return;
    }
    await _tts.speakSearchResults(_results, query: _ctrl.text.trim());
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
              hintText: _isRecording ? '正在听您说…' : '输入或语音说出要找的物品…',
              onSubmitted: (t) => _search(t),
              leading: Icon(
                _isRecording ? Icons.mic : Icons.search,
                color: _isRecording ? Colors.red : null,
              ),
              trailing: [
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic_none),
                  tooltip: _isRecording ? '停止并搜索' : '语音搜索',
                  color: _isRecording ? Colors.red : null,
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
          if (_isRecording)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '语音搜索中 $_recordSeconds 秒，再次点击麦克风结束',
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
              child: Text('已添加的物品（点击可搜索）', style: Theme.of(context).textTheme.titleSmall),
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
                        return ActionChip(
                          avatar: const Icon(Icons.inventory_2, size: 18),
                          label: Text(label, overflow: TextOverflow.ellipsis),
                          onPressed: () {
                            _ctrl.text = label;
                            _search(label);
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
