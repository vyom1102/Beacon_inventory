import 'dart:convert';
import 'dart:io';

import 'inventory_store.dart';

class InventoryApi {
  static const baseUrl = String.fromEnvironment(
    'BEACON_API_URL',
    defaultValue: 'https://maps.iwayplus.in/api/beacon-inventory',
  );
  static bool get isConfigured => baseUrl.isNotEmpty;

  Future<Map<String, dynamic>> _request(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    if (!isConfigured) {
      throw StateError('Set BEACON_API_URL to use shared inventory.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      final data = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{};
      if (response.statusCode >= 400) {
        throw StateError(
          data['message']?.toString() ?? 'Server error ${response.statusCode}',
        );
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> saveMovement({
    required String barcode,
    required MovementDirection direction,
    required String venue,
    required String personName,
    required String reason,
    required String reference,
    required String remarks,
    required String bluetoothId,
    required bool? isActive,
    required int? batteryPercent,
  }) async {
    // A stable request ID makes an HTTP retry safe if the response is lost.
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-$barcode';
    await _request('POST', '/movements', {
      'requestId': requestId,
      'barcode': barcode,
      'direction': direction.value,
      'venue': venue,
      'personName': personName,
      'reason': reason,
      'reference': reference,
      'remarks': remarks,
      'bluetoothId': bluetoothId,
      'isActive': isActive,
      'batteryPercent': batteryPercent,
    });
  }

  Future<List<ScanRecord>> recentMovements() async {
    final data = await _request('GET', '/movements?limit=500');
    return (data['movements'] as List)
        .cast<Map<String, dynamic>>()
        .map(_record)
        .toList();
  }

  Future<Map<String, dynamic>> dashboard() => _request('GET', '/dashboard');

  Future<List<ScanRecord>> history(String barcode) async {
    final data = await _request(
      'GET',
      '/beacons/${Uri.encodeComponent(barcode)}/history',
    );
    return (data['movements'] as List)
        .cast<Map<String, dynamic>>()
        .map(_record)
        .toList();
  }

  ScanRecord _record(Map<String, dynamic> value) => ScanRecord.fromMap({
    'id': 0,
    'barcode': value['barcode'],
    'direction': value['direction'],
    'venue': value['venue'],
    'person_name': value['personName'],
    'reason': value['reason'],
    'reference': value['reference'],
    'remarks': value['remarks'],
    'bluetooth_id': value['bluetoothId'],
    'is_active': value['isActive'],
    'battery_percent': value['batteryPercent'],
    'scanned_at': value['recordedAt'],
  });
}
