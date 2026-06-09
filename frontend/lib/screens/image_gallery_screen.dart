import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../widgets/item_image.dart';

class ImageGalleryScreen extends StatefulWidget {
  final int refreshToken;
  const ImageGalleryScreen({super.key, this.refreshToken = 0});

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  final _api = ApiClient();
  List<dynamic> _items = [];
  bool _loading = true;
  String _sortBy = 'time';
  bool _descending = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant ImageGalleryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final locId = context.read<AppState>().activeLocationId;
      final q = [
        'sort_by=$_sortBy',
        'descending=$_descending',
        if (locId.isNotEmpty) 'location_id=$locId',
      ].join('&');
      final data = await _api.get('/items/gallery?$q');
      _items = data is List ? data : [];
    } catch (_) {
      _items = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  void _openImage(Map<String, dynamic> item) {
    final url = item['image_url']?.toString();
    if (url == null || url.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: ItemImage(remoteUrl: url, fit: BoxFit.contain),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    [
                      item['label']?.toString() ?? '',
                      item['breadcrumb']?.toString() ?? '',
                      _formatTime(item['created_at']),
                    ].where((e) => e.isNotEmpty).join('\n'),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'time', label: Text('按时间')),
                    ButtonSegment(value: 'space', label: Text('按位置')),
                  ],
                  selected: {_sortBy},
                  onSelectionChanged: (s) {
                    setState(() => _sortBy = s.first);
                    _load();
                  },
                ),
              ),
              IconButton(
                icon: Icon(_descending ? Icons.arrow_downward : Icons.arrow_upward),
                onPressed: () {
                  setState(() => _descending = !_descending);
                  _load();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('共 ${_items.length} 张', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('暂无拍照记录'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i] as Map<String, dynamic>;
                        return InkWell(
                          onTap: () => _openImage(item),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: ItemImage(remoteUrl: item['image_url']?.toString())),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    item['label']?.toString() ?? '未命名',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                                  child: Text(
                                    _sortBy == 'space'
                                        ? (item['breadcrumb']?.toString() ?? '')
                                        : _formatTime(item['created_at']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
