import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'beacon_packet.dart';

class NearbyBeacon {
  const NearbyBeacon({
    required this.id,
    required this.name,
    required this.rssi,
    required this.seenAt,
    this.batteryPercent,
  });

  final String id;
  final String name;
  final int rssi;
  final DateTime seenAt;
  final int? batteryPercent;
}

class BeaconPresence extends ChangeNotifier {
  BeaconPresence._();
  static final instance = BeaconPresence._();

  static const freshness = Duration(minutes: 2);
  static const suggestionFreshness = Duration(seconds: 20);
  static const suggestionMinRssi =
      -50; // RSSI is negative dBm; -50 is stronger than -60.

  final Map<String, NearbyBeacon> _byId = {};
  final Map<String, NearbyBeacon> _byName = {};
  StreamSubscription<List<ScanResult>>? _subscription;
  Future<void>? _starting;
  Future<void>? _stopping;
  Future<void>? _oneShot;
  bool _scanning = false;
  bool _checking = false;
  String? _scanError;
  DateTime? _lastScanStartedAt;

  bool get scanning => _scanning;
  bool get checking => _checking;
  String? get scanError => _scanError;
  bool get hasRecentScan =>
      _lastScanStartedAt != null &&
      DateTime.now().difference(_lastScanStartedAt!) < freshness &&
      _scanError == null;
  List<NearbyBeacon> get nearby => _fresh(_byId.values, freshness);

  List<NearbyBeacon> get suggestions {
    final byName = <String, NearbyBeacon>{};
    for (final beacon in _fresh(_byId.values, suggestionFreshness)) {
      if (beacon.rssi < suggestionMinRssi || beacon.name.isEmpty) continue;
      final key = beacon.name.toLowerCase();
      if ((byName[key]?.rssi ?? -999) < beacon.rssi) byName[key] = beacon;
    }
    return _fresh(byName.values, suggestionFreshness);
  }

  List<NearbyBeacon> _fresh(Iterable<NearbyBeacon> values, Duration age) {
    final now = DateTime.now();
    return values.where((item) => now.difference(item.seenAt) < age).toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  NearbyBeacon? match(String barcode, {String bluetoothId = ''}) {
    final name = barcode.trim().toLowerCase();
    final id = bluetoothId.trim().toLowerCase();
    final now = DateTime.now();
    for (final candidate in [_byName[name], if (id.isNotEmpty) _byId[id]]) {
      if (candidate != null && now.difference(candidate.seenAt) < freshness) {
        return candidate;
      }
    }
    return null;
  }

  bool isActive(String barcode, {String bluetoothId = ''}) =>
      match(barcode, bluetoothId: bluetoothId) != null;

  int? batteryPercent(String barcode, {String bluetoothId = ''}) =>
      match(barcode, bluetoothId: bluetoothId)?.batteryPercent;

  void start() {
    _ensureSubscription();
    scan();
  }

  void _ensureSubscription() {
    _subscription ??= FlutterBluePlus.onScanResults.listen(
      _recordResults,
      onError: (Object error) {
        debugPrint('BLE scan results error: $error');
        _scanError = 'Bluetooth scan unavailable. Check app permissions.';
        _scanning = false;
        notifyListeners();
      },
    );
  }

  void _recordResults(List<ScanResult> results) {
    for (final result in results) {
      final id = result.device.remoteId.str;
      final name =
          (result.advertisementData.advName.isNotEmpty
                  ? result.advertisementData.advName
                  : result.device.platformName)
              .trim();
      if (!name.startsWith('IW')) continue;
      final manufacturerPayloads =
          result.advertisementData.manufacturerData.values;
      final packet =
          BeaconPacket.fromManufacturerData(name, manufacturerPayloads) ??
          BeaconPacket.fromAdvertisement(name, [
            ...manufacturerPayloads,
            ...result.advertisementData.serviceData.values,
          ]);
      final previous = _byId[id.toLowerCase()];
      final previousIsFresh =
          previous != null &&
          previous.name == name &&
          result.timeStamp.difference(previous.seenAt) < freshness;
      final beacon = NearbyBeacon(
        id: id,
        name: name,
        rssi: result.rssi,
        seenAt: result.timeStamp,
        batteryPercent:
            packet?.estimatedBatteryPercent ??
            (previousIsFresh ? previous.batteryPercent : null),
      );
      if ((_byId[id.toLowerCase()]?.seenAt ??
              DateTime.fromMillisecondsSinceEpoch(0))
          .isBefore(beacon.seenAt)) {
        _byId[id.toLowerCase()] = beacon;
      }
      if (beacon.name.isNotEmpty &&
          (_byName[beacon.name.toLowerCase()]?.seenAt ??
                  DateTime.fromMillisecondsSinceEpoch(0))
              .isBefore(beacon.seenAt)) {
        _byName[beacon.name.toLowerCase()] = beacon;
      }
    }
    notifyListeners();
  }

  // Continuous scanning is started only by the nearby-beacon finder page.
  Future<void> scan() => _starting ??= _startScan().whenComplete(() {
    _starting = null;
  });

  Future<void> _startScan({Duration? timeout}) async {
    await _stopping;
    if (_scanning) return;
    _scanError = null;
    notifyListeners();
    try {
      if (!await FlutterBluePlus.isSupported) {
        _scanError = 'Bluetooth scanning is not supported on this device.';
        return;
      }
      if (await FlutterBluePlus.adapterState.first !=
          BluetoothAdapterState.on) {
        _scanError = 'Turn on Bluetooth to check this beacon.';
        return;
      }
      await FlutterBluePlus.startScan(
        continuousUpdates: timeout == null,
        removeIfGone: timeout == null ? const Duration(seconds: 20) : null,
        timeout: timeout,
        androidUsesFineLocation: true,
      );
      _lastScanStartedAt = DateTime.now();
      _scanning = true;
      if (timeout != null) {
        await FlutterBluePlus.isScanning.where((value) => !value).first;
        _scanning = false;
      }
    } catch (error) {
      debugPrint('BLE scan unavailable: $error');
      _scanError =
          'Bluetooth scan unavailable. Check Bluetooth and app permissions.';
    } finally {
      notifyListeners();
    }
  }

  // A user-initiated check on the inventory form; never leaves BLE running.
  Future<void> scanOnce() => _oneShot ??= _runOneShot().whenComplete(() {
    _oneShot = null;
  });

  Future<void> _runOneShot() async {
    _checking = true;
    _lastScanStartedAt = null;
    notifyListeners();
    try {
      await stop();
      _byId.clear();
      _byName.clear();
      _ensureSubscription();
      await _startScan(timeout: const Duration(seconds: 5));
    } catch (error) {
      debugPrint('BLE check unavailable: $error');
      _scanError =
          'Bluetooth scan unavailable. Check Bluetooth and app permissions.';
      notifyListeners();
    } finally {
      await stop();
      _checking = false;
      notifyListeners();
    }
  }

  Future<void> stop() => _stopping ??= _stop().whenComplete(() {
    _stopping = null;
  });

  Future<void> _stop() async {
    await _starting;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (error) {
      debugPrint('BLE scan could not stop: $error');
    }
    _scanning = false;
    notifyListeners();
  }
}
