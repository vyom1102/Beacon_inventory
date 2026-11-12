import 'package:beacon_inventory/beacon_packet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'decodes battery from first manufacturer byte as localization_engine does',
    () {
      final packet = BeaconPacket.fromManufacturerData('IW25030199', [
        [0x5a, 0x12, 0xf4, 0x00, 0x64, 0x00, 0x00],
      ]);
      expect(packet?.batteryVoltage, 2.8125);
      expect(packet?.estimatedBatteryPercent, 81);
    },
  );

  test('ignores unrelated and incomplete manufacturer payloads', () {
    expect(
      BeaconPacket.fromManufacturerData('OTHER', [
        [0x5a, 0, 0, 0, 0, 0, 0],
      ]),
      isNull,
    );
    expect(
      BeaconPacket.fromManufacturerData('IW25030199', [
        [0x5a],
      ]),
      isNull,
    );
  });

  test('decodes InPlay name and battery voltage byte', () {
    final packet = BeaconPacket.parse([
      0x0b, 0x09,
      ...'IW25030199'.codeUnits,
      0, 0, 0, 1,
      0x60, // 96 / 32 = 3.0 V
    ]);
    expect(packet?.name, 'IW25030199');
    expect(packet?.batteryVoltage, 3.0);
    expect(packet?.estimatedBatteryPercent, 100);
  });

  test('does not invent battery for unrelated advertisements', () {
    expect(BeaconPacket.parse([1, 2, 3]), isNull);
    expect(BeaconPacket.parse([...List.filled(14, 0), 0x60]), isNull);
  });

  test('decodes name separated from the InPlay payload', () {
    final packet = BeaconPacket.fromAdvertisement('IW25030199', [
      [0, 0, 0, 1, 0x5a], // 2.8125 V after the four-byte identifier
    ]);
    expect(packet?.name, 'IW25030199');
    expect(packet?.batteryVoltage, 2.8125);
    expect(packet?.estimatedBatteryPercent, 81);
  });

  test('finds the name packet after a leading manufacturer prefix', () {
    final packet = BeaconPacket.parse([
      0x01,
      0x02,
      0x0b,
      0x09,
      ...'IW25030199'.codeUnits,
      0,
      0,
      0,
      1,
      0x60,
    ]);
    expect(packet?.name, 'IW25030199');
    expect(packet?.estimatedBatteryPercent, 100);
  });
}
