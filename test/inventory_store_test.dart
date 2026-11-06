import 'package:beacon_inventory/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan record reads persisted barcode and movement fields', () {
    final scan = ScanRecord.fromMap({
      'id': 7,
      'barcode': 'IW25030199',
      'direction': 'out',
      'venue': 'Main warehouse',
      'person_name': 'Asha Kumar',
      'reason': 'Sent to event',
      'reference': 'DEP-123',
      'remarks': 'Handled with care',
      'bluetooth_id': 'AA:BB:CC:DD:EE:FF',
      'scanned_at': '2026-10-31T05:30:00.000Z',
    });

    expect(scan.id, 7);
    expect(scan.barcode, 'IW25030199');
    expect(scan.direction, MovementDirection.outbound);
    expect(scan.venue, 'Main warehouse');
    expect(scan.personName, 'Asha Kumar');
    expect(scan.reason, 'Sent to event');
    expect(scan.reference, 'DEP-123');
    expect(scan.remarks, 'Handled with care');
    expect(scan.bluetoothId, 'AA:BB:CC:DD:EE:FF');
    expect(scan.scannedAt, DateTime.utc(2026, 10, 31, 5, 30));
  });
}
