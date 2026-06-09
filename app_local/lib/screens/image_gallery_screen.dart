import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/item_repository.dart';
import '../services/local_file_service.dart';
import '../widgets/item_image.dart';

class ImageGalleryScreen extends StatefulWidget {
  final int refreshToken;
  const ImageGalleryScreen({super.key, this.refreshToken = 0});

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  final _itemRepo = ItemRepository();
  final _localFiles = LocalFileService();
  List<Map<String, dynamic>> _items = [];
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
    if (oldWidget.refreshToken != widget.refreshToken) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _storagePath = await _localFiles.imagesRootPath();
    // 不按住所过滤，避免 JOIN 异常导致有记录却看不到图
    _items = await _itemRepo.listWithImages(
      sortBy: _sortBy,
      descending: _descending,
    );
    if (mounted) setState(() => _loading = false);
  }

  bool _hasImage(Map<String, dynamic> item) {
    final path = item['local_image_path']?.toString() ?? '';
    final remote = item['remote_image_url']?.toString() ?? '';
    return path.isNotEmpty || remote.isNotEmpty;
  }

  void _openImage(Map<String, dynamic> item) {
    if (!_hasImage(item)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该物品没有关联图片')),
      );
      return;
    }
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
                child: ItemImage(
                  localPath: item['local_image_path']?.toString(),
                  remoteUrl: item['remote_image_url']?.toString(),
                  fit: BoxFit.contain,
                ),
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
                      if (item['local_image_path'] != null)
                        '本地: ${item['local_image_path']}',
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
                tooltip: _descending ? '降序' : '升序',
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            '共 ${_items.length} 条带图记录（保存在应用私有目录，无需相册权限）\n$_storagePath',
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
                          '暂无拍照记录。\n请通过「拍照识别」拍照并确认入库后，图片会出现在这里。\n'
                          '（仅语音添加的物品不含图片）',
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
                                Expanded(
                                  child: ItemImage(
                                    localPath: item['local_image_path']?.toString(),
                                    remoteUrl: item['remote_image_url']?.toString(),
                                  ),
                                ),
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
