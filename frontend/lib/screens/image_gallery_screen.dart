import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../services/api_client.dart';
import '../services/item_media_store.dart';
import '../services/local_file_service.dart';
import '../widgets/item_image.dart';

class ImageGalleryScreen extends StatefulWidget {
  final int refreshToken;
  const ImageGalleryScreen({super.key, this.refreshToken = 0});

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _GalleryEntry {
  final String localPath;
  final DateTime modified;
  final String? itemId;
  final String label;
  final String breadcrumb;

  const _GalleryEntry({
    required this.localPath,
    required this.modified,
    this.itemId,
    required this.label,
    required this.breadcrumb,
  });
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  final _api = ApiClient();
  final _localFiles = LocalFileService();
  final _mediaStore = ItemMediaStore();

  List<_GalleryEntry> _items = [];
  bool _loading = true;
  String _sortBy = 'time';
  bool _descending = true;
  String _storagePath = '';

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
    _storagePath = await _localFiles.imagesRootPath();
    if (!mounted) return;
    final locId = context.read<AppState>().activeLocationId;

    try {
      final images = await _localFiles.listAllImages();
      final pathToItem = await _mediaStore.imagePathToItemId();
      final itemIds = pathToItem.values.toSet().toList();

      final metaById = <String, Map<String, dynamic>>{};
      if (itemIds.isNotEmpty) {
        try {
          final data = await _api.post('/items/lookup', body: {'ids': itemIds});
          if (data is List) {
            for (final row in data) {
              if (row is Map) {
                final id = row['id']?.toString();
                if (id != null) metaById[id] = Map<String, dynamic>.from(row);
              }
            }
          }
        } catch (_) {}
      }

      final entries = <_GalleryEntry>[];
      for (final img in images) {
        final itemId = pathToItem[img.path];
        final meta = itemId != null ? metaById[itemId] : null;
        if (locId.isNotEmpty && meta != null && meta['location_id'] != locId) {
          continue;
        }
        entries.add(
          _GalleryEntry(
            localPath: img.path,
            modified: img.modified,
            itemId: itemId,
            label: meta?['label']?.toString() ?? (itemId != null ? '已入库物品' : '拍照原图'),
            breadcrumb: meta?['breadcrumb']?.toString() ?? (itemId != null ? '' : '未关联物品'),
          ),
        );
      }

      entries.sort((a, b) {
        if (_sortBy == 'space') {
          final c = a.breadcrumb.compareTo(b.breadcrumb);
          if (c != 0) return _descending ? -c : c;
        }
        final t = a.modified.compareTo(b.modified);
        return _descending ? -t : t;
      });

      _items = entries;
    } catch (_) {
      _items = [];
    }

    if (mounted) setState(() => _loading = false);
  }

  void _openImage(_GalleryEntry item) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: ItemImage(localPath: item.localPath, fit: BoxFit.contain),
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
                      item.label,
                      item.breadcrumb,
                      _formatTime(item.modified),
                      '本地: ${item.localPath}',
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
      if (raw is DateTime) {
        return DateFormat('yyyy-MM-dd HH:mm').format(raw);
      }
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
          child: Text(
            '共 ${_items.length} 张原始图片（保存在应用私有目录）\n$_storagePath',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '暂无拍照记录。\n请通过「拍照识别」拍照并确认入库后，原图会出现在这里。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
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
                        final item = _items[i];
                        return InkWell(
                          onTap: () => _openImage(item),
                          child: Card(
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: ItemImage(localPath: item.localPath)),
                                Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    item.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                                  child: Text(
                                    _sortBy == 'space'
                                        ? (item.breadcrumb.isNotEmpty ? item.breadcrumb : '未关联位置')
                                        : _formatTime(item.modified),
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
