import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../app/app_state.dart';
import '../services/api_client.dart';

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
              ? const Center(child: Text('暂无平面图，点击右下角上传'))
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
                                onChanged: _load,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (p['image_url'] != null)
                                CachedNetworkImage(
                                  imageUrl: p['image_url'],
                                  height: 160,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) => const SizedBox(
                                    height: 160,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (_, __, ___) => const SizedBox(
                                    height: 160,
                                    child: Icon(Icons.broken_image, size: 48),
                                  ),
                                ),
                              ListTile(
                                title: Text('平面图 ${i + 1}'),
                                subtitle: Text('${anchors.length} 个区域标注'),
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
  final VoidCallback onChanged;

  const FloorPlanDetailScreen({
    super.key,
    required this.plan,
    required this.locationId,
    required this.onChanged,
  });

  @override
  State<FloorPlanDetailScreen> createState() => _FloorPlanDetailScreenState();
}

class _FloorPlanDetailScreenState extends State<FloorPlanDetailScreen> {
  final _api = ApiClient();
  List<dynamic> _zones = [];
  late Map<String, dynamic> _plan;

  @override
  void initState() {
    super.initState();
    _plan = Map<String, dynamic>.from(widget.plan as Map);
    _loadZones();
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

  Future<void> _addAnchorAt(Offset local, Size size) async {
    if (_zones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先创建分区')));
      return;
    }
    final x = (local.dx / size.width * 100).clamp(0, 100);
    final y = (local.dy / size.height * 100).clamp(0, 100);

    String? zoneId;
    final zoneName = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('关联分区'),
        children: _zones.map((z) {
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, z['id'] as String),
            child: Text(z['name'] ?? z['id']),
          );
        }).toList(),
      ),
    );
    if (zoneName == null) return;
    zoneId = zoneName;

    final zone = _zones.firstWhere((z) => z['id'] == zoneId);
    try {
      await _api.post('/floor-plans/${_plan['id']}/anchors', body: {
        'zone_id': zoneId,
        'label': zone['name'],
        'polygon_points': [
          {'x': x, 'y': y},
          {'x': x + 3, 'y': y},
          {'x': x + 3, 'y': y + 3},
          {'x': x, 'y': y + 3},
        ],
        'color': '#4A90D9',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('标注已添加')));
        await _reloadPlan();
        widget.onChanged();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final anchors = (_plan['anchors'] as List?) ?? [];
    final url = _plan['image_url']?.toString() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('平面图标注')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('点击图片添加分区标注（显示为彩色区域）', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          ),
          Expanded(
            child: InteractiveViewer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapUp: (d) => _addAnchorAt(d.localPosition, Size(constraints.maxWidth, constraints.maxHeight)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (url.isNotEmpty)
                          CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)
                        else
                          const Center(child: Icon(Icons.image_not_supported, size: 64)),
                        CustomPaint(
                          painter: _AnchorPainter(anchors),
                          child: Container(),
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
              height: 100,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: anchors.map((a) {
                  return Chip(
                    avatar: CircleAvatar(backgroundColor: _parseColor(a['color']), radius: 8),
                    label: Text(a['label'] ?? '区域'),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Color _parseColor(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length < 7) return Colors.blue;
    final v = int.parse(hex.substring(1), radix: 16);
    return Color(0xFF000000 | v);
  }
}

class _AnchorPainter extends CustomPainter {
  final List<dynamic> anchors;
  _AnchorPainter(this.anchors);

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in anchors) {
      final pts = (a['polygon_points'] as List?) ?? [];
      if (pts.length < 3) continue;
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
      final color = _color(a['color']);
      canvas.drawPath(path, Paint()..color = color.withAlpha(80));
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  Color _color(String? hex) {
    if (hex == null || !hex.startsWith('#') || hex.length < 7) return Colors.blue;
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  @override
  bool shouldRepaint(covariant _AnchorPainter old) => old.anchors != anchors;
}

/// Open floor plan for the active location from space tab.
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
