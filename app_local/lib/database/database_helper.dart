import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  static Future<Database> _init() async {
    final path = join(await getDatabasesPath(), 'homelocus_local.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE locations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            is_default INTEGER DEFAULT 0,
            created_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE zones (
            id TEXT PRIMARY KEY,
            location_id TEXT NOT NULL,
            name TEXT NOT NULL,
            FOREIGN KEY(location_id) REFERENCES locations(id)
          )''');
        await db.execute('''
          CREATE TABLE containers (
            id TEXT PRIMARY KEY,
            zone_id TEXT NOT NULL,
            name TEXT NOT NULL,
            FOREIGN KEY(zone_id) REFERENCES zones(id)
          )''');
        await db.execute('''
          CREATE TABLE slots (
            id TEXT PRIMARY KEY,
            container_id TEXT NOT NULL,
            name TEXT NOT NULL,
            level INTEGER DEFAULT 0,
            FOREIGN KEY(container_id) REFERENCES containers(id)
          )''');
        await db.execute('''
          CREATE TABLE items (
            id TEXT PRIMARY KEY,
            slot_id TEXT NOT NULL,
            label TEXT NOT NULL,
            brand TEXT,
            category TEXT,
            color TEXT,
            purpose TEXT,
            tags TEXT,
            local_image_path TEXT,
            remote_image_url TEXT,
            raw_recognition TEXT,
            is_chargeable INTEGER DEFAULT 0,
            is_deleted INTEGER DEFAULT 0,
            deleted_at TEXT,
            created_at TEXT,
            updated_at TEXT,
            FOREIGN KEY(slot_id) REFERENCES slots(id)
          )''');
        await db.execute('''
          CREATE TABLE reminders (
            id TEXT PRIMARY KEY,
            item_id TEXT,
            type TEXT NOT NULL,
            title TEXT,
            next_remind_at TEXT,
            is_done INTEGER DEFAULT 0
          )''');
        await db.execute(
            'CREATE INDEX idx_items_slot ON items(slot_id)');
        await db.execute(
            'CREATE INDEX idx_items_deleted ON items(is_deleted)');
      },
    );
  }
}
