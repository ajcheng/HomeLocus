import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';

class SpaceRepository {
  final _uuid = const Uuid();

  Future<void> ensureSeedData() async {
    final db = await DatabaseHelper.database;
    final count = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM locations')) ??
        0;
    if (count > 0) return;

    final locId = 'loc_${_uuid.v4().substring(0, 8)}';
    final now = DateTime.now().toIso8601String();
    await db.insert('locations', {
      'id': locId,
      'name': '我的家',
      'is_default': 1,
      'created_at': now,
    });

    final templates = [
      ('客厅', '电视柜', ['上层', '中层', '下层']),
      ('主卧', '衣柜', ['挂衣区', '抽屉1', '抽屉2']),
    ];

    for (final (zoneName, containerName, slots) in templates) {
      final zoneId = 'zone_${_uuid.v4().substring(0, 8)}';
      await db.insert('zones', {
        'id': zoneId,
        'location_id': locId,
        'name': zoneName,
      });
      final containerId = 'ctr_${_uuid.v4().substring(0, 8)}';
      await db.insert('containers', {
        'id': containerId,
        'zone_id': zoneId,
        'name': containerName,
      });
      for (var i = 0; i < slots.length; i++) {
        await db.insert('slots', {
          'id': 'slot_${_uuid.v4().substring(0, 8)}',
          'container_id': containerId,
          'name': slots[i],
          'level': i,
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> listLocations() async {
    final db = await DatabaseHelper.database;
    return db.query('locations', orderBy: 'is_default DESC, name');
  }

  Future<List<Map<String, dynamic>>> listZones(String locationId) async {
    final db = await DatabaseHelper.database;
    return db.query('zones',
        where: 'location_id = ?', whereArgs: [locationId], orderBy: 'name');
  }

  Future<List<Map<String, dynamic>>> listContainers(String zoneId) async {
    final db = await DatabaseHelper.database;
    return db.query('containers',
        where: 'zone_id = ?', whereArgs: [zoneId], orderBy: 'name');
  }

  Future<List<Map<String, dynamic>>> listSlots(String containerId) async {
    final db = await DatabaseHelper.database;
    return db.query('slots',
        where: 'container_id = ?',
        whereArgs: [containerId],
        orderBy: 'level, name');
  }

  Future<String> createLocation(String name, {bool isDefault = false}) async {
    final db = await DatabaseHelper.database;
    final id = 'loc_${_uuid.v4().substring(0, 8)}';
    if (isDefault) {
      await db.update('locations', {'is_default': 0});
    }
    await db.insert('locations', {
      'id': id,
      'name': name.trim(),
      'is_default': isDefault ? 1 : 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<String> createZone(String locationId, String name) async {
    final db = await DatabaseHelper.database;
    final id = 'zone_${_uuid.v4().substring(0, 8)}';
    await db.insert('zones', {
      'id': id,
      'location_id': locationId,
      'name': name.trim(),
    });
    return id;
  }

  Future<String> createContainer(String zoneId, String name) async {
    final db = await DatabaseHelper.database;
    final id = 'ctr_${_uuid.v4().substring(0, 8)}';
    await db.insert('containers', {
      'id': id,
      'zone_id': zoneId,
      'name': name.trim(),
    });
    return id;
  }

  Future<String> createSlot(String containerId, String name, {int? level}) async {
    final db = await DatabaseHelper.database;
    final slots = await listSlots(containerId);
    final nextLevel = level ?? (slots.isEmpty ? 0 : (slots.last['level'] as int) + 1);
    final id = 'slot_${_uuid.v4().substring(0, 8)}';
    await db.insert('slots', {
      'id': id,
      'container_id': containerId,
      'name': name.trim(),
      'level': nextLevel,
    });
    return id;
  }

  Future<void> setDefaultLocation(String locationId) async {
    final db = await DatabaseHelper.database;
    await db.update('locations', {'is_default': 0});
    await db.update('locations', {'is_default': 1}, where: 'id = ?', whereArgs: [locationId]);
  }

  Future<void> renameLocation(String id, String name) async {
    final db = await DatabaseHelper.database;
    await db.update('locations', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameZone(String id, String name) async {
    final db = await DatabaseHelper.database;
    await db.update('zones', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameContainer(String id, String name) async {
    final db = await DatabaseHelper.database;
    await db.update('containers', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> renameSlot(String id, String name) async {
    final db = await DatabaseHelper.database;
    await db.update('slots', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countItemsInLocation(String locationId) async {
    final ids = await _slotIdsForLocation(locationId);
    return _countItemsInSlots(ids);
  }

  Future<int> countItemsInZone(String zoneId) async {
    final ids = await _slotIdsForZone(zoneId);
    return _countItemsInSlots(ids);
  }

  Future<int> countItemsInContainer(String containerId) async {
    final ids = await _slotIdsForContainer(containerId);
    return _countItemsInSlots(ids);
  }

  Future<int> countItemsInSlot(String slotId) async {
    return _countItemsInSlots([slotId]);
  }

  Future<void> deleteLocation(String locationId) async {
    final db = await DatabaseHelper.database;
    final slotIds = await _slotIdsForLocation(locationId);
    await db.transaction((txn) async {
      await _archiveItemsInSlots(txn, slotIds);
      for (final zoneId in await _zoneIdsForLocationTxn(txn, locationId)) {
        await _deleteZoneTxn(txn, zoneId);
      }
      await txn.delete('locations', where: 'id = ?', whereArgs: [locationId]);
    });
  }

  Future<void> deleteZone(String zoneId) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await _deleteZoneTxn(txn, zoneId);
    });
  }

  Future<void> deleteContainer(String containerId) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await _deleteContainerTxn(txn, containerId);
    });
  }

  Future<void> deleteSlot(String slotId) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await _archiveItemsInSlots(txn, [slotId]);
      await txn.delete('slots', where: 'id = ?', whereArgs: [slotId]);
    });
  }

  Future<List<String>> _slotIdsForLocation(String locationId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT s.id AS id FROM slots s
      JOIN containers c ON s.container_id = c.id
      JOIN zones z ON c.zone_id = z.id
      WHERE z.location_id = ?
    ''', [locationId]);
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<List<String>> _slotIdsForZone(String zoneId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT s.id AS id FROM slots s
      JOIN containers c ON s.container_id = c.id
      WHERE c.zone_id = ?
    ''', [zoneId]);
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<List<String>> _slotIdsForContainer(String containerId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.query('slots', columns: ['id'], where: 'container_id = ?', whereArgs: [containerId]);
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<int> _countItemsInSlots(List<String> slotIds) async {
    if (slotIds.isEmpty) return 0;
    final db = await DatabaseHelper.database;
    final ph = List.filled(slotIds.length, '?').join(',');
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM items WHERE is_deleted = 0 AND slot_id IN ($ph)',
      slotIds,
    ));
    return count ?? 0;
  }

  Future<void> _archiveItemsInSlots(DatabaseExecutor txn, List<String> slotIds) async {
    if (slotIds.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    final ph = List.filled(slotIds.length, '?').join(',');
    await txn.rawUpdate(
      'UPDATE items SET is_deleted = 1, deleted_at = ?, updated_at = ? WHERE is_deleted = 0 AND slot_id IN ($ph)',
      [now, now, ...slotIds],
    );
  }

  Future<List<String>> _zoneIdsForLocationTxn(DatabaseExecutor txn, String locationId) async {
    final rows = await txn.query('zones', columns: ['id'], where: 'location_id = ?', whereArgs: [locationId]);
    return rows.map((r) => r['id'] as String).toList();
  }

  Future<void> _deleteZoneTxn(DatabaseExecutor txn, String zoneId) async {
    final containers = await txn.query('containers', columns: ['id'], where: 'zone_id = ?', whereArgs: [zoneId]);
    for (final c in containers) {
      await _deleteContainerTxn(txn, c['id'] as String);
    }
    await txn.delete('zones', where: 'id = ?', whereArgs: [zoneId]);
  }

  Future<void> _deleteContainerTxn(DatabaseExecutor txn, String containerId) async {
    final slotIds = (await txn.query('slots', columns: ['id'], where: 'container_id = ?', whereArgs: [containerId]))
        .map((r) => r['id'] as String)
        .toList();
    await _archiveItemsInSlots(txn, slotIds);
    await txn.delete('slots', where: 'container_id = ?', whereArgs: [containerId]);
    await txn.delete('containers', where: 'id = ?', whereArgs: [containerId]);
  }

  Future<String> breadcrumbForSlot(String slotId) async {
    final db = await DatabaseHelper.database;
    final rows = await db.rawQuery('''
      SELECT l.name loc, z.name zone, c.name ctr, s.name slot
      FROM slots s
      JOIN containers c ON s.container_id = c.id
      JOIN zones z ON c.zone_id = z.id
      JOIN locations l ON z.location_id = l.id
      WHERE s.id = ?
    ''', [slotId]);
    if (rows.isEmpty) return '';
    final r = rows.first;
    return '${r['loc']} / ${r['zone']} / ${r['ctr']} / ${r['slot']}';
  }
}
