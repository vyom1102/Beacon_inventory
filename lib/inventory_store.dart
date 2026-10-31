import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

enum MovementDirection {
  inbound('in'),
  outbound('out');

  const MovementDirection(this.value);

  final String value;

  String get label => value;
}

class ScanRecord {
  const ScanRecord({
    required this.id,
    required this.barcode,
    required this.direction,
    required this.venue,
    required this.reason,
    required this.scannedAt,
  });

  final int id;
  final String barcode;
  final MovementDirection direction;
  final String venue;
  final String reason;
  final DateTime scannedAt;

  factory ScanRecord.fromMap(Map<String, Object?> row) => ScanRecord(
    id: row['id']! as int,
    barcode: row['barcode']! as String,
    direction: row['direction'] == 'in'
        ? MovementDirection.inbound
        : MovementDirection.outbound,
    venue: row['venue']! as String,
    reason: row['reason']! as String,
    scannedAt: DateTime.parse(row['scanned_at']! as String),
  );
}

class InventoryStore {
  InventoryStore._();

  static final InventoryStore instance = InventoryStore._();
  static const _databaseName = 'beacon_inventory.db';
  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final databasePath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(databasePath, _databaseName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            direction TEXT NOT NULL CHECK(direction IN ('in', 'out')),
            venue TEXT NOT NULL,
            reason TEXT NOT NULL,
            scanned_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX scans_barcode ON scans(barcode, id DESC)',
        );
      },
    );
    return _database!;
  }

  Future<List<ScanRecord>> getScans() async {
    final rows = await (await _db).query('scans', orderBy: 'id DESC');
    return rows.map(ScanRecord.fromMap).toList(growable: false);
  }

  Future<void> saveScan({
    required String barcode,
    required String venue,
    required String reason,
    required MovementDirection direction,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final previous = await transaction.query(
        'scans',
        columns: ['direction'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (previous.isNotEmpty &&
          previous.first['direction'] == direction.value) {
        throw StateError(
          'This beacon is already ${direction.value.toUpperCase()}. '
          'Choose the other status.',
        );
      }
      await transaction.insert('scans', {
        'barcode': barcode,
        'direction': direction.value,
        'venue': venue,
        'reason': reason,
        'scanned_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }
}
