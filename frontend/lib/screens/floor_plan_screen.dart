import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../app/app_state.dart';
import '../services/api_client.dart';

const _zoneColors = [
  '#4A90D9',
  '#E67E22',
  '#27AE60',
  '#9B59B6',
  '#E74C3C',
  '#1ABC9C',
  '#F39C12',
];

/// Compute [BoxFit.contain] rect for [imageSize] inside [containerSize].
Rect fitContainRect(Size containerSize, Size imageSize) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return Offset.zero & containerSize;
  }
  final scale = math.min(
    containerSize.width / imageSize.width,
    containerSize.height / imageSize.height,
  );
  final w = imageSize.width * scale;
  final h = imageSize.height * scale;
  return Rect.fromLTWH(
    (containerSize.width - w) / 2,
    (containerSize.height - h) / 2,
    w,
    h,
  );
}

Offset? percentFromLocal(Offset local, Rect imageRect) {
  if (!imageRect.contains(local)) return null;
  return Offset(
    (local.dx - imageRect.left) / imageRect.width * 100,
    (local.dy - imageRect.top) / imageRect.height * 100,
  );
}

bool hitPolygon(List<dynamic> pts, Offset percent) {
  if (pts.length < 3) return false;
  final path = Path();
  for (var i = 0; i < pts.length; i++) {
    final x = (pts[i]['x'] as num).toDouble();
    final y = (pts[i]['y'] as num).toDouble();
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path.contains(percent);
}

class FloorPlanScreen extends StatefulWidget {
  final String locationId;
  final String locationName;

  const FloorPlanScreen({super.key, required this.locationId, required this.locationName});

  @override
  State<FloorPlanScreen> createState() => _FloorPlanScreenState();
}

class _FloorPlanScreenState extends State<FloorPlanScreen> {
  final _api = ApiClient();
  List<dynamic> _plans = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.get('/floor-plans/${widget.locationId}');
      setState(() => _plans = data is List ? data : []);
    } catch (_) {
      setState(() => _plans = []);
    }
    setState(() => _loading = false);
  }

  Future<void> _uploadPlan() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 4096);
    if (picked == null) return;
    try {
      await _api.uploadMultipart('/floor-plans/${widget.locationId}/upload', File(picked.path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('平面图已上传')));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deletePlan(dynamic plan) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除平面图'),
        content: const Text('确定删除该平面图及所有区域标注？'),
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
      await _api.delete('/floor-plans/${plan['id']}');
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('平面图 · ${widget.locationName}')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploadPlan,
        icon: const Icon(Icons.upload),
        label: const Text('上传平面图'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('暂无平面图'),
                      const SizedBox(height: 8),
                      Text('上传户型图后可框选客厅、卧室等分区', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: _plans.length,
                    itemBuilder: (_, i) {
                      final p = _plans[i];
                      final anchors = (p['anchors'] as List?) ?? [];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FloorPlanDetailScreen(
                                plan: p,
                                locationId: widget.locationId,
                                locationName: widget.locationName,
                                onChanged: _load,
                              ),
                            ),
                          ),
                          onLongPress: () => _deletePlan(p),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (p['image_url'] != null)
                                CachedNetworkImage(
                                  imageUrl: p['image_url'],
                                  height: 160,
                                  fit: BoxFit.cover,
                                ),
                              ListTile(
                                title: Text('平面图 ${i + 1}'),
                                subtitle: Text('${anchors.length} 个分区标注 · 长按删除'),
                                trailing: const Icon(Icons.chevron_right),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class FloorPlanDetailScreen extends StatefulWidget {
  final dynamic plan;
  final String locationId;
  final String locationName;
  final VoidCallback onChanged;

  const FloorPlanDetailScreen({
    super.key,
    required this.plan,
    required this.locationId,
    required this.locationName,
    required this.onChanged,
  });

  @override
  State<FloorPlanDetailScreen> createState() => _FloorPlanDetailScreenState();
}

class _FloorPlanDetailScreenState extends State<FloorPlanDetailScreen> {
  final _api = ApiClient();
  List<dynamic> _zones = [];
  late Map<String, dynamic> _plan;
  bool _drawMode = false;
  Size? _imageSize;
  Rect? _draftRect;
  Offset? _dragStart;

  @override
  void initState() {
    super.initState();
    _plan = Map<String, dynamic>.from(widget.plan as Map);
    _loadZones();
    _resolveImageSize(_plan['image_url']?.toString() ?? '');
  }

  Future<void> _resolveImageSize(String url) async {
    if (url.isEmpty) return;
    try {
      final provider = CachedNetworkImageProvider(url);
      final stream = provider.resolve(const ImageConfiguration());
      stream.addListener(ImageStreamListener((info, _) {
        if (mounted) {
          setState(() {
            _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
      }));
    } catch (_) {}
  }

  Future<void> _reloadPlan() async {
    try {
      final list = await _api.get('/floor-plans/${widget.locationId}');
      if (list is List) {
        final found = list.cast<Map>().firstWhere(
          (p) => p['id'] == _plan['id'],
          orElse: () => _plan,
        );
        setState(() => _plan = Map<String, dynamic>.from(found));
      }
    } catch (_) {}
  }

  Future<void> _loadZones() async {
    try {
      final data = await _api.get('/space/zones?location_id=${widget.locationId}');
      setState(() => _zones = data is List ? data : []);
    } catch (_) {}
  }

  String _colorForZone(String zoneId) {
    final idx = _zones.indexWhere((z) => z['id'] == zoneId);
    if (idx < 0) return _zoneColors[0];
    return _zoneColors[idx % _zoneColors.length];
  }

  List<Map<String, double>> _rectToPolygon(Rect r) {
    return [
      {'x': r.left, 'y': r.top},
      {'x': r.right, 'y': r.top},
      {'x': r.right, 'y': r.bottom},
      {'x': r.left, 'y': r.bottom},
    ];
  }

  Future<void> _saveDrawnRect(Rect percentRect) async {
    if (_zones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在空间页创建分区')));
      return;
    }
    if (percentRect.width < 2 || percentRect.height < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('区域太小，请重新框选')));
      return;
    }

    final zoneId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('关联到分区'),
        children: _zones.map((z) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, z['id'] as String),
            child: Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: _parseColor(_colorForZone(z['id'])),
                const SizedBox(width: 10),
                Text(z['name'] ?? z['id']),
              ],
            ),
          );
        }).toList(),
      ),
    );
    if (zoneId == null) return;

    final zone = _zones.firstWhere((z) => z['id'] == zoneId);
    try {
      await _api.post('/floor-plans/${_plan['id']}/anchors', body: {
        'zone_id': zoneId,
        'label': zone['name'],
        'polygon_points': _rectToPolygon(percentRect),
        'color': _colorForZone(zoneId),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已标注「${zone['name']}」')));
        setState(() => _draftRect = null);
        await _reloadPlan();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  dynamic _hitAnchor(Offset percent, List<dynamic> anchors) {
    for (final a in anchors.reversed) {
      final pts = (a['polygon_points'] as List?) ?? [];
      if (hitPolygon(pts, percent)) return a;
    }
    return null;
  }

  void _openZone(dynamic anchor) {
    final zoneId = anchor['zone_id']?.toString() ?? '';
    if (zoneId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('该标注未关联分区')));
      return;
    }
    context.read<AppState>().openZoneInSpace(
      zoneId,
      locationId: widget.locationId,
      locationName: widget.locationName,
    );
    Navigator.popUntil(context, (r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已跳转到分区：${anchor['label'] ?? ''}')),
    );
  }

  Future<void> _deleteAnchor(dynamic anchor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${anchor['label'] ?? '标注'}」？'),
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
      await _api.delete('/floor-plans/anchors/${anchor['id']}');
      await _reloadPlan();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _onCanvasTap(Offset local, Rect imageRect, List<dynamic> anchors) {
    final pct = percentFromLocal(local, imageRect);
    if (pct == null) return;

    final hit = _hitAnchor(pct, anchors);
    if (hit != null) {
      if (_drawMode) {
        _deleteAnchor(hit);
      } else {
        _openZone(hit);
      }
      return;
    }
    if (!_drawMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未点中分区。开启「框选模式」可拖拽绘制区域')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchors = (_plan['anchors'] as List?) ?? [];
    final url = _plan['image_url']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('平面图'),
        actions: [
          IconButton(
            tooltip: _drawMode ? '浏览模式' : '框选模式',
            icon: Icon(_drawMode ? Icons.pan_tool_alt : Icons.crop_free),
            onPressed: () => setState(() {
              _drawMode = !_drawMode;
              _draftRect = null;
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('删除平面图'),
                    content: const Text('确定删除？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) {
                  await _api.delete('/floor-plans/${_plan['id']}');
                  widget.onChanged();
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('删除平面图'))],
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: _drawMode ? Colors.orange.shade50 : Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(_drawMode ? Icons.crop_free : Icons.touch_app, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _drawMode
                          ? '框选模式：在图上拖拽绘制矩形区域，松手后选择分区'
                          : '浏览模式：点击彩色区域跳转到对应分区',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final container = Size(constraints.maxWidth, constraints.maxHeight);
                  final imgSize = _imageSize ?? const Size(16, 9);
                  final imageRect = fitContainRect(container, imgSize);

                  return GestureDetector(
                    onTapUp: (d) => _onCanvasTap(d.localPosition, imageRect, anchors),
                    onPanStart: _drawMode
                        ? (d) {
                            final p = percentFromLocal(d.localPosition, imageRect);
                            if (p != null) setState(() => _dragStart = p);
                          }
                        : null,
                    onPanUpdate: _drawMode
                        ? (d) {
                            final p = percentFromLocal(d.localPosition, imageRect);
                            if (p != null && _dragStart != null) {
                              setState(() {
                                _draftRect = Rect.fromPoints(_dragStart!, p);
                              });
                            }
                          }
                        : null,
                    onPanEnd: _drawMode
                        ? (_) async {
                            if (_draftRect != null) {
                              final r = _draftRect!;
                              await _saveDrawnRect(r);
                            }
                            setState(() {
                              _dragStart = null;
                              _draftRect = null;
                            });
                          }
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url.isNotEmpty)
                          Positioned.fromRect(
                            rect: imageRect,
                            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.fill),
                          )
                        else
                          const Center(child: Icon(Icons.image_not_supported, size: 64)),
                        Positioned.fromRect(
                          rect: imageRect,
                          child: CustomPaint(
                            painter: _AnchorPainter(
                              anchors: anchors,
                              draftRect: _draftRect,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (anchors.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已标注分区', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: anchors.map((a) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: CircleAvatar(
                              backgroundColor: _parseColor(a['color']),
                              radius: 8,
                            ),
                            label: Text(a['label'] ?? '区域'),
                            onPressed: () => _openZone(a),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length < 7) return Colors.blue;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }
}

class _AnchorPainter extends CustomPainter {
  final List<dynamic> anchors;
  final Rect? draftRect;

  _AnchorPainter({required this.anchors, this.draftRect});

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in anchors) {
      _paintPolygon(canvas, size, (a['polygon_points'] as List?) ?? [], _color(a['color']));
      _paintLabel(canvas, size, a);
    }
    if (draftRect != null) {
      final r = draftRect!;
      final rect = Rect.fromLTWH(
        r.left / 100 * size.width,
        r.top / 100 * size.height,
        r.width / 100 * size.width,
        r.height / 100 * size.height,
      );
      canvas.drawRect(
        rect,
        Paint()..color = Colors.orange.withAlpha(100)..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        rect,
        Paint()..color = Colors.orange..style = PaintingStyle.stroke..strokeWidth = 2,
      );
    }
  }

  void _paintPolygon(Canvas canvas, Size size, List<dynamic> pts, Color color) {
    if (pts.length < 3) return;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final px = (pts[i]['x'] as num).toDouble() / 100 * size.width;
      final py = (pts[i]['y'] as num).toDouble() / 100 * size.height;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withAlpha(90));
    canvas.drawPath(
      path,
      Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.5,
    );
  }

  void _paintLabel(Canvas canvas, Size size, dynamic anchor) {
    final pts = (anchor['polygon_points'] as List?) ?? [];
    if (pts.isEmpty) return;
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += (p['x'] as num).toDouble();
      cy += (p['y'] as num).toDouble();
    }
    cx = cx / pts.length / 100 * size.width;
    cy = cy / pts.length / 100 * size.height;

    final label = anchor['label']?.toString() ?? '';
    if (label.isEmpty) return;

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.3);

    final bg = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: tp.width + 8, height: tp.height + 4),
      const Radius.circular(4),
    );
    canvas.drawRRect(bg, Paint()..color = Colors.black.withAlpha(160));
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  Color _color(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length < 7) return Colors.blue;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  bool shouldRepaint(covariant _AnchorPainter old) =>
      old.anchors != anchors || old.draftRect != draftRect;
}

void openFloorPlan(BuildContext context) {
  final app = context.read<AppState>();
  final locId = app.activeLocationId;
  if (locId.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先选择地点')));
    return;
  }
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FloorPlanScreen(locationId: locId, locationName: app.activeLocationName),
    ),
  );
}
