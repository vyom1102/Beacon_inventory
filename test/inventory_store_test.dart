import 'package:beacon_inventory/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan record reads persisted barcode and movement fields', () {
    final scan = ScanRecord.fromMap({
      'id': 7,
      'barcode': 'IW25030199',
      'direction': 'out',
      'venue': 'Main warehouse',
      'reason': 'Sent to event',
      'scanned_at': '2026-10-31T05:30:00.000Z',
    });

    expect(scan.id, 7);
    expect(scan.barcode, 'IW25030199');
    expect(scan.direction, MovementDirection.outbound);
    expect(scan.venue, 'Main warehouse');
    expect(scan.reason, 'Sent to event');
    expect(scan.scannedAt, DateTime.utc(2026, 10, 31, 5, 30));
  });
}
