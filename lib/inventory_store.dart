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
    required this.personName,
    required this.reason,
    required this.reference,
    required this.remarks,
    required this.bluetoothId,
    required this.isActive,
    required this.batteryPercent,
    required this.scannedAt,
  });

  final int id;
  final String barcode;
  final MovementDirection direction;
  final String venue;
  final String personName;
  final String reason;
  final String reference;
  final String remarks;
  final String bluetoothId;
  final bool? isActive;
  final int? batteryPercent;
  final DateTime scannedAt;

  factory ScanRecord.fromMap(Map<String, Object?> row) => ScanRecord(
    id: row['id']! as int,
    barcode: row['barcode']! as String,
    direction: row['direction'] == 'in'
        ? MovementDirection.inbound
        : MovementDirection.outbound,
    venue: row['venue']! as String,
    personName: (row['person_name'] as String?) ?? '',
    reason: row['reason']! as String,
    reference: (row['reference'] as String?) ?? '',
    remarks: (row['remarks'] as String?) ?? '',
    bluetoothId: (row['bluetooth_id'] as String?) ?? '',
    isActive: row['is_active'] == null
        ? null
        : row['is_active'] == 1 || row['is_active'] == true,
    batteryPercent: row['battery_percent'] as int?,
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
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scans (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode TEXT NOT NULL,
            direction TEXT NOT NULL CHECK(direction IN ('in', 'out')),
            venue TEXT NOT NULL,
            person_name TEXT NOT NULL,
            reason TEXT NOT NULL,
            reference TEXT NOT NULL DEFAULT '',
            remarks TEXT NOT NULL DEFAULT '',
            bluetooth_id TEXT NOT NULL DEFAULT '',
            is_active INTEGER,
            battery_percent INTEGER,
            scanned_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX scans_barcode ON scans(barcode, id DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE scans ADD COLUMN person_name TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE scans ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE scans ADD COLUMN remarks TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE scans ADD COLUMN bluetooth_id TEXT NOT NULL DEFAULT ''",
          );
        }
        if (oldVersion < 5) {
          await db.execute('ALTER TABLE scans ADD COLUMN is_active INTEGER');
          await db.execute(
            'ALTER TABLE scans ADD COLUMN battery_percent INTEGER',
          );
        }
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
    required String personName,
    required String reason,
    required String reference,
    required String remarks,
    required String bluetoothId,
    required bool? isActive,
    required int? batteryPercent,
    required MovementDirection direction,
  }) async {
    final db = await _db;
    await db.transaction((transaction) async {
      final previous = await transaction.query(
        'scans',
        columns: ['direction', 'bluetooth_id'],
        where: 'barcode = ?',
        whereArgs: [barcode],
        orderBy: 'id DESC',
        limit: 1,
      );
      if (previous.isEmpty && direction == MovementDirection.outbound) {
        throw StateError('Mark this beacon IN before marking it OUT.');
      }
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
        'person_name': personName,
        'reason': reason,
        'reference': reference,
        'remarks': remarks,
        'bluetooth_id': bluetoothId.isNotEmpty
            ? bluetoothId
            : (previous.isEmpty ? '' : previous.first['bluetooth_id'] ?? ''),
        'is_active': isActive == null ? null : (isActive ? 1 : 0),
        'battery_percent': batteryPercent,
        'scanned_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }
}
