import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';

class ItemRepository {
  final _uuid = const Uuid();

  Future<List<Map<String, dynamic>>> listBySlot(String slotId,
      {bool includeDeleted = false}) async {
    final db = await DatabaseHelper.database;
    return db.query(
      'items',
      where: includeDeleted ? 'slot_id = ?' : 'slot_id = ? AND is_deleted = 0',
      whereArgs: [slotId],
      orderBy: 'updated_at DESC',
    );
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('items', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> insert({
    required String slotId,
    required String label,
    String? brand,
    String? category,
    String? color,
    String? purpose,
    List<String> tags = const [],
    String? localImagePath,
    String? remoteImageUrl,
    String? rawRecognition,
    bool isChargeable = false,
  }) async {
    final db = await DatabaseHelper.database;
    final id = 'item_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().toIso8601String();
    await db.insert('items', {
      'id': id,
      'slot_id': slotId,
      'label': label,
      'brand': brand,
      'category': category,
      'color': color,
      'purpose': purpose,
      'tags': jsonEncode(tags),
      'local_image_path': localImagePath,
      'remote_image_url': remoteImageUrl,
      'raw_recognition': rawRecognition,
      'is_chargeable': isChargeable ? 1 : 0,
      'is_deleted': 0,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> updateTags(String itemId, List<String> tags) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'items',
      {
        'tags': jsonEncode(tags),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> softDelete(String itemId) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'items',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<int> archiveByTag(String tag) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('items', where: 'is_deleted = 0');
    var count = 0;
    final now = DateTime.now().toIso8601String();
    for (final row in rows) {
      final tags = _parseTags(row['tags']);
      if (tags.contains(tag)) {
        await db.update('items', {
          'is_deleted': 1,
          'deleted_at': now,
          'updated_at': now,
        }, where: 'id = ?', whereArgs: [row['id']]);
        count++;
      }
    }
    return count;
  }

  Future<List<Map<String, dynamic>>> search({
    String? text,
    String? tag,
    bool includeHistory = false,
    String? locationId,
    int limit = 50,
  }) async {
    final db = await DatabaseHelper.database;
    final where = <String>[];
    final args = <Object?>[];

    if (includeHistory) {
      where.add('i.is_deleted = 1');
    } else {
      where.add('i.is_deleted = 0');
    }

    if (locationId != null && locationId.isNotEmpty) {
      where.add('l.id = ?');
      args.add(locationId);
    }

    final query = text?.trim() ?? '';
    if (query.isNotEmpty) {
      final terms = query
          .split(RegExp(r'[\s,，、]+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      for (final term in terms) {
        where.add('''(
          i.label LIKE ? OR i.brand LIKE ? OR i.category LIKE ? OR i.color LIKE ?
          OR i.purpose LIKE ? OR i.raw_recognition LIKE ? OR i.tags LIKE ?
        )''');
        final p = '%$term%';
        args.addAll(List.filled(7, p));
      }
    }

    final sql = '''
      SELECT i.*, l.name loc, z.name zone, c.name ctr, s.name slot
      FROM items i
      LEFT JOIN slots s ON i.slot_id = s.id
      LEFT JOIN containers c ON s.container_id = c.id
      LEFT JOIN zones z ON c.zone_id = z.id
      LEFT JOIN locations l ON z.location_id = l.id
      WHERE ${where.join(' AND ')}
      ORDER BY ${includeHistory ? 'i.deleted_at' : 'i.updated_at'} DESC
      LIMIT $limit
    ''';
    var rows = await db.rawQuery(sql, args);

    if (tag != null && tag.isNotEmpty) {
      rows = rows.where((r) => _parseTags(r['tags']).contains(tag)).toList();
    }

    return rows.map(_withBreadcrumb).toList();
  }

  Future<List<Map<String, dynamic>>> listWithImages({
    String? locationId,
    String sortBy = 'time',
    bool descending = true,
    int limit = 200,
  }) async {
    final db = await DatabaseHelper.database;
    final where = <String>[
      'i.is_deleted = 0',
      "i.local_image_path IS NOT NULL",
      "i.local_image_path != ''",
    ];
    final args = <Object?>[];

    if (locationId != null && locationId.isNotEmpty) {
      where.add('l.id = ?');
      args.add(locationId);
    }

    final order = sortBy == 'space'
        ? 'l.name ${descending ? 'DESC' : 'ASC'}, z.name ${descending ? 'DESC' : 'ASC'}, '
            'c.name ${descending ? 'DESC' : 'ASC'}, s.name ${descending ? 'DESC' : 'ASC'}, '
            'i.created_at DESC'
        : 'i.created_at ${descending ? 'DESC' : 'ASC'}';

    final sql = '''
      SELECT i.*, l.name loc, z.name zone, c.name ctr, s.name slot
      FROM items i
      LEFT JOIN slots s ON i.slot_id = s.id
      LEFT JOIN containers c ON s.container_id = c.id
      LEFT JOIN zones z ON c.zone_id = z.id
      LEFT JOIN locations l ON z.location_id = l.id
      WHERE ${where.join(' AND ')}
      ORDER BY $order
      LIMIT $limit
    ''';
    final rows = await db.rawQuery(sql, args);
    return rows.map(_withBreadcrumb).toList();
  }

  Map<String, dynamic> _withBreadcrumb(Map<String, dynamic> row) {
    final r = Map<String, dynamic>.from(row);
    final parts = [r['loc'], r['zone'], r['ctr'], r['slot']]
        .where((e) => e != null && e.toString().isNotEmpty)
        .map((e) => e.toString())
        .toList();
    r['breadcrumb'] = parts.isEmpty ? '未关联位置' : parts.join(' / ');
    return r;
  }

  Future<List<Map<String, dynamic>>> listMarkStats({bool history = false}) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(
      'items',
      where: history ? 'is_deleted = 1' : 'is_deleted = 0',
    );
    final counts = <String, int>{};
    for (final row in rows) {
      for (final t in _parseTags(row['tags'])) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.entries
        .map((e) => {'tag': e.key, 'count': e.value})
        .toList()
      ..sort((a, b) => (a['tag'] as String).compareTo(b['tag'] as String));
  }

  List<String> _parseTags(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }
}
