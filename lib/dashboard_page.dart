import 'package:flutter/material.dart';

import 'beacon_presence.dart';
import 'inventory_api.dart';
import 'inventory_store.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.inventoryBuilder});
  final WidgetBuilder inventoryBuilder;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  Map<String, List<ScanRecord>> _venues = {};
  int _inCount = 0;
  int _outCount = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final groups = <String, List<ScanRecord>>{};
      var inCount = 0;
      var outCount = 0;
      if (InventoryApi.isConfigured) {
        final data = await InventoryApi().dashboard();
        inCount = data['inCount'] as int;
        outCount = data['outCount'] as int;
        for (final group in data['venues'] as List) {
          final entry = group as Map<String, dynamic>;
          groups[entry['name'] as String] = (entry['beacons'] as List)
              .map(
                (item) =>
                    InventoryApiRecord.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }
      } else {
        final latest = <String, ScanRecord>{};
        for (final scan in await InventoryStore.instance.getScans()) {
          latest.putIfAbsent(scan.barcode, () => scan);
        }
        for (final scan in latest.values) {
          if (scan.direction == MovementDirection.inbound) {
            inCount++;
          } else {
            outCount++;
          }
          final venue = scan.direction == MovementDirection.inbound
              ? 'Inventory'
              : scan.venue;
          groups.putIfAbsent(venue, () => []).add(scan);
        }
      }
      if (!mounted) return;
      setState(() {
        _venues = groups;
        _inCount = inCount;
        _outCount = outCount;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openHistory(String barcode) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BeaconHistoryPage(barcode: barcode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Beacon inventory')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () async {
        await Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: widget.inventoryBuilder));
        _load();
      },
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text('Record movement'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (!InventoryApi.isConfigured)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'Local mode: shared inventory is not configured in this build.',
                ),
              ),
            ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          if (!_loading && _error == null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _countCard('Total beacons', _inCount + _outCount),
                _countCard('In inventory', _inCount),
                _countCard('Out', _outCount),
                _countCard('Venues', _venues.length),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Venue wise inventory',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (_venues.isEmpty) const Text('No beacons recorded yet.'),
            ..._venues.entries.map(
              (group) => Card(
                child: ExpansionTile(
                  title: Text(group.key),
                  subtitle: Text('${group.value.length} beacons'),
                  children: group.value
                      .map(
                        (scan) => AnimatedBuilder(
                          animation: BeaconPresence.instance,
                          builder: (context, _) => ListTile(
                            title: Text(scan.barcode),
                            subtitle: Text(
                              '${scan.direction == MovementDirection.inbound ? 'IN' : 'OUT'} · '
                              '${scan.isActive == null
                                  ? 'BLE unknown'
                                  : scan.isActive!
                                  ? 'BLE active'
                                  : 'BLE not detected'}'
                              '${scan.batteryPercent == null ? '' : ' · Battery ~${scan.batteryPercent}%'}',
                            ),
                            trailing:
                                BeaconPresence.instance.isActive(
                                  scan.barcode,
                                  bluetoothId: scan.bluetoothId,
                                )
                                ? const Chip(label: Text('Active'))
                                : const Icon(Icons.chevron_right),
                            onTap: () => _openHistory(scan.barcode),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _countCard(String label, int value) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 48) / 2,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    ),
  );
}

class InventoryApiRecord {
  static ScanRecord fromJson(Map<String, dynamic> item) => ScanRecord.fromMap({
    'id': 0,
    'barcode': item['barcode'],
    'direction': item['direction'],
    'venue': item['venue'],
    'person_name': item['personName'],
    'reason': item['reason'],
    'reference': item['reference'],
    'remarks': item['remarks'],
    'bluetooth_id': item['bluetoothId'],
    'is_active': item['isActive'],
    'battery_percent': item['batteryPercent'],
    'scanned_at': item['recordedAt'],
  });
}

class BeaconHistoryPage extends StatefulWidget {
  const BeaconHistoryPage({super.key, required this.barcode});
  final String barcode;

  @override
  State<BeaconHistoryPage> createState() => _BeaconHistoryPageState();
}

class _BeaconHistoryPageState extends State<BeaconHistoryPage> {
  late final Future<List<ScanRecord>> _history = _load();

  Future<List<ScanRecord>> _load() async {
    if (InventoryApi.isConfigured) {
      return InventoryApi().history(widget.barcode);
    }
    final all = (await InventoryStore.instance.getScans())
        .where((scan) => scan.barcode == widget.barcode)
        .toList();
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month - 3, now.day);
    final recent = all.where((scan) => scan.scannedAt.isAfter(cutoff)).toList();
    return recent.isEmpty ? all.take(1).toList() : recent;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.barcode)),
    body: FutureBuilder<List<ScanRecord>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final scans = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AnimatedBuilder(
              animation: BeaconPresence.instance,
              builder: (context, _) => Text(
                BeaconPresence.instance.isActive(
                      widget.barcode,
                      bluetoothId: scans.isEmpty ? '' : scans.first.bluetoothId,
                    )
                    ? 'Active · detected nearby in the last 2 minutes'
                    : 'Not detected nearby',
              ),
            ),
            if (scans.isNotEmpty)
              Text(
                'Last saved check: ${scans.first.isActive == null
                    ? 'unknown'
                    : scans.first.isActive!
                    ? 'active'
                    : 'not detected'}'
                '${scans.first.batteryPercent == null ? '' : ' · Battery ~${scans.first.batteryPercent}%'}',
              ),
            const SizedBox(height: 16),
            Text(
              scans.length == 1 &&
                      scans.first.scannedAt.isBefore(
                        DateTime(
                          DateTime.now().year,
                          DateTime.now().month - 3,
                          DateTime.now().day,
                        ),
                      )
                  ? 'Last recorded movement'
                  : 'Movements in the past 3 months',
            ),
            ...scans.map(
              (scan) => Card(
                child: ListTile(
                  title: Text(
                    '${scan.direction.label.toUpperCase()} · ${scan.venue}',
                  ),
                  subtitle: Text(
                    '${scan.personName} · ${scan.reason}\n${scan.scannedAt.toLocal()}',
                  ),
                  isThreeLine: true,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
