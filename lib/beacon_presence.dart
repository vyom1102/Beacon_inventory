import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BeaconPresence extends ChangeNotifier {
  BeaconPresence._();
  static final instance = BeaconPresence._();

  final Map<String, DateTime> _seen = {};
  StreamSubscription<List<ScanResult>>? _subscription;
  Timer? _timer;
  bool _scanning = false;

  bool isActive(String barcode, {String bluetoothId = ''}) {
    final seen =
        _seen[barcode.trim().toLowerCase()] ??
        (bluetoothId.isEmpty ? null : _seen[bluetoothId.trim().toLowerCase()]);
    return seen != null &&
        DateTime.now().difference(seen) < const Duration(minutes: 2);
  }

  void start() {
    _subscription ??= FlutterBluePlus.onScanResults.listen((results) {
      final now = DateTime.now();
      for (final result in results) {
        for (final identity in [
          result.advertisementData.advName,
          result.device.platformName,
          result.device.remoteId.str,
        ]) {
          if (identity.trim().isNotEmpty) {
            _seen[identity.trim().toLowerCase()] = now;
          }
        }
      }
      notifyListeners();
    });
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => scan());
    scan();
  }

  Future<void> scan() async {
    if (_scanning) return;
    _scanning = true;
    try {
      if (await FlutterBluePlus.isSupported) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      }
    } catch (error) {
      debugPrint('BLE scan unavailable: $error');
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (error) {
      debugPrint('BLE scan could not stop: $error');
    }
  }
}
