class BeaconPacket {
  const BeaconPacket({required this.name, required this.batteryVoltage});

  final String name;
  final double batteryVoltage;

  // localization_engine exposes manufacturer data without the two-byte
  // manufacturer ID. Its first payload byte is the battery voltage value.
  static BeaconPacket? fromManufacturerData(
    String advertisedName,
    Iterable<List<int>> payloads,
  ) {
    final name = advertisedName.trim();
    if (!name.startsWith('IW')) return null;
    for (final payload in payloads) {
      if (payload.length < 7) continue;
      final voltage = payload.first * 0.03125;
      if (voltage >= 1.8 && voltage <= 3.6) {
        return BeaconPacket(name: name, batteryVoltage: voltage);
      }
    }
    return null;
  }

  // InPlay layout: 10-byte name, 4-byte identifier, 1 battery byte (1/32 V).
  static BeaconPacket? parse(List<int> bytes) {
    var offset = 0;
    for (var i = 0; i + 1 < bytes.length; i++) {
      if (bytes[i] == 0x0b && bytes[i + 1] == 0x09) {
        offset = i + 2;
        break;
      }
    }
    if (bytes.length < offset + 15) return null;
    final name = String.fromCharCodes(
      bytes.skip(offset).take(10),
    ).replaceAll(RegExp(r'\x00+$'), '').trim();
    if (!RegExp(r'^IW[A-Za-z0-9]{4,8}$').hasMatch(name)) return null;
    final voltage = bytes[offset + 14] * 0.03125;
    if (voltage < 1.8 || voltage > 3.6) return null;
    return BeaconPacket(name: name, batteryVoltage: voltage);
  }

  // Flutter separates the local name from the rest of an advertisement.
  // The backend packet layout places the four-byte InPlay identifier and
  // voltage byte immediately after that ten-byte name.
  static BeaconPacket? fromAdvertisement(
    String advertisedName,
    Iterable<List<int>> payloads,
  ) {
    for (final payload in payloads) {
      final complete = parse(payload);
      if (complete != null) return complete;
    }
    if (!RegExp(r'^IW[A-Za-z0-9]{4,8}$').hasMatch(advertisedName)) {
      return null;
    }
    for (final payload in payloads) {
      if (payload.length < 5) continue;
      final paddedName = <int>[
        ...advertisedName.codeUnits,
        ...List<int>.filled(10 - advertisedName.length, 0),
      ];
      for (final offset in [0, 2]) {
        if (payload.length < offset + 5) continue;
        final parsed = parse([...paddedName, ...payload.skip(offset)]);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  // Voltage-derived estimate. A manufacturer discharge curve is unavailable.
  int get estimatedBatteryPercent =>
      ((batteryVoltage - 2.0) * 100).round().clamp(0, 100);
}
