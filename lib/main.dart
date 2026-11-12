import 'dart:async';
import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'inventory_store.dart';
import 'inventory_api.dart';
import 'dashboard_page.dart';
import 'beacon_presence.dart';
import 'scanner_page.dart';
import 'nearby_beacon_page.dart';

const _forest = Color(0xFF173B32);
const _lime = Color(0xFFB8EA68);
const _background = Color(0xFFF5F7F3);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BeaconInventoryApp());
}

class BeaconInventoryApp extends StatelessWidget {
  const BeaconInventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Inventory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _forest,
          primary: _forest,
          secondary: _lime,
          surface: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDCE5DC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFDCE5DC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF83B765), width: 1.5),
          ),
        ),
      ),
      home: const InventoryPage(),
    );
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _venueController = TextEditingController();
  final _personController = TextEditingController();
  final _reasonController = TextEditingController();
  final _referenceController = TextEditingController();
  final _remarksController = TextEditingController();
  final _bluetoothIdController = TextEditingController();
  final _barcodeController = TextEditingController();

  List<ScanRecord> _scans = [];
  MovementDirection _direction = MovementDirection.inbound;
  String? _selectedReason;
  List<String> get _reasonOptions => _direction == MovementDirection.inbound
      ? const [
          'New Purchase',
          'Extra Return from Installation',
          'Not Working',
          'Repaired Lot',
          'Removed from Demo Deployment',
          'Return from Internal Testing',
          'Other',
        ]
      : const [
          'New Deployment',
          'Demo Deployment',
          'Sent for Repair',
          'Issued for Internal Testing',
          'Replacement in Existing Deployment',
          'Other',
        ];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  Timer? _bluetoothCheckTimer;
  bool _formVisible = true;
  bool _appResumed = true;

  Map<String, ScanRecord> get _latestByBarcode {
    final latest = <String, ScanRecord>{};
    for (final scan in _scans) {
      latest.putIfAbsent(scan.barcode, () => scan);
    }
    return latest;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadScans();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBluetooth());
    _bluetoothCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkBluetooth(),
    );
  }

  void _checkBluetooth() {
    if (mounted && _formVisible && _appResumed) {
      BeaconPresence.instance.scanOnce();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appResumed = state == AppLifecycleState.resumed;
    if (_appResumed) {
      _checkBluetooth();
    } else {
      BeaconPresence.instance.stop();
    }
  }

  @override
  void dispose() {
    _bluetoothCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    BeaconPresence.instance.stop();
    _venueController.dispose();
    _personController.dispose();
    _reasonController.dispose();
    _referenceController.dispose();
    _remarksController.dispose();
    _bluetoothIdController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadScans() async {
    try {
      final scans = InventoryApi.isConfigured
          ? await InventoryApi().recentMovements()
          : await InventoryStore.instance.getScans();
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _loading = false;
        _loadError = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load saved scans: $error';
      });
    }
  }

  Future<void> _openScanner() async {
    _formVisible = false;
    await BeaconPresence.instance.stop();
    if (!mounted) return;
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    _formVisible = true;
    if (!mounted) return;
    if (barcode == null) return;
    setState(() => _barcodeController.text = barcode);
    final presence = BeaconPresence.instance;
    final bluetoothId = _latestByBarcode[barcode]?.bluetoothId ?? '';
    if (presence.match(barcode, bluetoothId: bluetoothId) == null) {
      _checkBluetooth();
    }
  }

  Future<void> _openNearbyBeacons() async {
    _formVisible = false;
    final beacon = await Navigator.of(context).push<NearbyBeacon>(
      MaterialPageRoute<NearbyBeacon>(builder: (_) => const NearbyBeaconPage()),
    );
    await BeaconPresence.instance.stop();
    _formVisible = true;
    if (!mounted || beacon == null) return;
    setState(() {
      _barcodeController.text = beacon.name;
      _bluetoothIdController.text = beacon.id;
    });
  }

  Future<void> _openInventory() async {
    _formVisible = false;
    await BeaconPresence.instance.stop();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const DashboardPage()));
    _formVisible = true;
    if (mounted) _loadScans();
  }

  Future<void> _saveScan() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final save = InventoryApi.isConfigured
          ? InventoryApi().saveMovement
          : InventoryStore.instance.saveScan;
      final barcode = _barcodeController.text.trim();
      final bluetoothId = _bluetoothIdController.text.trim().isNotEmpty
          ? _bluetoothIdController.text.trim()
          : _latestByBarcode[barcode]?.bluetoothId ?? '';
      final presence = BeaconPresence.instance;
      final isActive = presence.hasRecentScan
          ? presence.isActive(barcode, bluetoothId: bluetoothId)
          : null;
      await save(
        barcode: barcode,
        venue: _venueController.text.trim(),
        personName: _personController.text.trim(),
        reason: _selectedReason == 'Other'
            ? _reasonController.text.trim()
            : _selectedReason!,
        reference: _referenceController.text.trim(),
        remarks: _remarksController.text.trim(),
        bluetoothId: bluetoothId,
        isActive: isActive,
        batteryPercent: isActive == true
            ? presence.batteryPercent(barcode, bluetoothId: bluetoothId)
            : null,
        direction: _direction,
      );
      _barcodeController.clear();
      await _loadScans();
      if (!mounted) return;
      _showMessage('Movement recorded successfully.');
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Could not save this scan: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _exportScans() async {
    if (_scans.isEmpty) {
      _showMessage('There are no scans to export yet.', isError: true);
      return;
    }

    try {
      final workbook = Excel.createExcel();
      final sheet = workbook['Scan log'];
      sheet.appendRow([
        TextCellValue('Scan time (UTC)'),
        TextCellValue('Barcode'),
        TextCellValue('Status'),
        TextCellValue('Venue name'),
        TextCellValue('Venue direction'),
        TextCellValue('Person name'),
        TextCellValue('Reason'),
        TextCellValue('Reference / Document No.'),
        TextCellValue('Remarks'),
      ]);
      for (final scan in _scans.reversed) {
        sheet.appendRow([
          TextCellValue(scan.scannedAt.toUtc().toIso8601String()),
          TextCellValue(scan.barcode),
          TextCellValue(scan.direction.label.toUpperCase()),
          TextCellValue(scan.venue),
          TextCellValue(
            scan.direction == MovementDirection.inbound ? 'From' : 'To',
          ),
          TextCellValue(scan.personName),
          TextCellValue(scan.reason),
          TextCellValue(scan.reference),
          TextCellValue(scan.remarks),
        ]);
      }

      final bytes = workbook.encode();
      if (bytes == null) {
        throw StateError('The spreadsheet could not be generated.');
      }
      final directory = await getTemporaryDirectory();
      final file = File(p.join(directory.path, 'beacon-scans.xlsx'));
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          text: 'Beacon inventory scan history',
        ),
      );
    } on StateError catch (error) {
      if (mounted) {
        _showMessage('Could not export scans: $error', isError: true);
      }
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Could not export scans: $error', isError: true);
      }
    }
  }

  void _showMessage(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: isError ? const Color(0xFFA3432F) : _forest,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beacon scanner'),
        actions: [
          IconButton(
            onPressed: _exportScans,
            tooltip: 'Export scan history',
            icon: const Icon(Icons.file_download_outlined),
          ),
          TextButton.icon(
            onPressed: _openInventory,
            icon: const Icon(Icons.inventory_2_outlined),
            label: const Text('Inventory'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadScans,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [
              _buildScanCard(),
              const SizedBox(height: 18),
              _buildRecentScans(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanCard() {
    final knownBeacon = _latestByBarcode[_barcodeController.text.trim()];
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
            eyebrow: 'NEW MOVEMENT',
            title: 'Record movement',
          ),
          const SizedBox(height: 18),
          SegmentedButton<MovementDirection>(
            segments: const [
              ButtonSegment(
                value: MovementDirection.inbound,
                icon: Icon(Icons.south_west_rounded),
                label: Text('IN'),
              ),
              ButtonSegment(
                value: MovementDirection.outbound,
                icon: Icon(Icons.north_east_rounded),
                label: Text('OUT'),
              ),
            ],
            selected: {_direction},
            onSelectionChanged: (selection) => setState(() {
              _direction = selection.first;
              _selectedReason = null;
            }),
          ),
          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('BEACON BARCODE'),
                TextFormField(
                  controller: _barcodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 150,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'e.g. IW25',
                    counterText: '',
                  ),
                  validator: (value) =>
                      _required(value, 'Scan or enter a barcode.'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openScanner,
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan barcode with camera'),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openNearbyBeacons,
                    icon: const Icon(Icons.bluetooth_searching),
                    label: const Text('Barcode unreadable? Find beacon'),
                  ),
                ),
                TextButton.icon(
                  onPressed: BeaconPresence.instance.scanOnce,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check beacon signal again'),
                ),
                if (knownBeacon != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    'Existing beacon · currently ${knownBeacon.direction.label.toUpperCase()} · '
                    'last seen at ${knownBeacon.venue}',
                    style: const TextStyle(
                      color: Color(0xFF43624A),
                      fontSize: 12,
                    ),
                  ),
                ],
                AnimatedBuilder(
                  animation: BeaconPresence.instance,
                  builder: (context, _) {
                    final presence = BeaconPresence.instance;
                    final barcode = _barcodeController.text.trim();
                    if (barcode.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final active = presence.isActive(
                      barcode,
                      bluetoothId: _bluetoothIdController.text.trim().isNotEmpty
                          ? _bluetoothIdController.text.trim()
                          : knownBeacon?.bluetoothId ?? '',
                    );
                    return Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            presence.checking
                                ? 'Checking for nearby Bluetooth signal…'
                                : presence.scanError != null
                                ? presence.scanError!
                                : active
                                ? 'Beacon active · detected nearby'
                                : !presence.hasRecentScan
                                ? 'Bluetooth checks automatically while this form is open. You can also check now.'
                                : 'Beacon not detected nearby.',
                            style: TextStyle(
                              color: active && !presence.checking
                                  ? const Color(0xFF467B25)
                                  : const Color(0xFFA3432F),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (active && !presence.checking)
                            Text(
                              presence.batteryPercent(
                                        _barcodeController.text,
                                        bluetoothId:
                                            _bluetoothIdController.text,
                                      ) ==
                                      null
                                  ? 'Battery unavailable in this advertisement.'
                                  : 'Estimated battery: ~${presence.batteryPercent(_barcodeController.text, bluetoothId: _bluetoothIdController.text)}%',
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                _fieldLabel(
                  _direction == MovementDirection.inbound
                      ? 'FROM VENUE NAME'
                      : 'TO VENUE NAME',
                ),
                TextFormField(
                  controller: _venueController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Main warehouse',
                    counterText: '',
                  ),
                  validator: (value) => _required(value, 'Enter a venue name.'),
                ),
                const SizedBox(height: 14),
                _fieldLabel('PERSON RESPONSIBLE'),
                TextFormField(
                  controller: _personController,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'Person responsible for this movement',
                    counterText: '',
                  ),
                  validator: (value) =>
                      _required(value, 'Enter the person’s name.'),
                ),
                const SizedBox(height: 14),
                _fieldLabel('REASON'),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  decoration: const InputDecoration(
                    hintText: 'Select a reason',
                  ),
                  items: _reasonOptions
                      .map(
                        (reason) => DropdownMenuItem(
                          value: reason,
                          child: Text(reason),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _selectedReason = value),
                  validator: (value) =>
                      value == null ? 'Select a reason.' : null,
                ),
                if (_selectedReason == 'Other') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _reasonController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      hintText: 'Type your reason',
                      counterText: '',
                    ),
                    validator: (value) => _required(value, 'Enter a reason.'),
                  ),
                ],
                const SizedBox(height: 14),
                _fieldLabel('REFERENCE / DOCUMENT NO. (OPTIONAL)'),
                TextFormField(
                  controller: _referenceController,
                  maxLength: 150,
                  decoration: const InputDecoration(
                    hintText: 'PO, invoice, deployment or repair reference',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 14),
                _fieldLabel('REMARKS (OPTIONAL)'),
                TextFormField(
                  controller: _remarksController,
                  maxLength: 300,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Additional details',
                    counterText: '',
                  ),
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  title: const Text('Advanced: Bluetooth ID'),
                  children: [
                    TextFormField(
                      controller: _bluetoothIdController,
                      maxLength: 150,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Bluetooth ID or MAC address',
                        counterText: '',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _saveScan,
                    style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: _forest,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Save movement',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward_rounded, size: 18),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentScans() {
    return _CardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(eyebrow: 'ACTIVITY LOG', title: 'Recent scans'),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_loadError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_loadError!, style: const TextStyle(color: Colors.red)),
                TextButton.icon(
                  onPressed: _loadScans,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            )
          else if (_scans.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No scans yet. Scan your first beacon to begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9BA99E), fontSize: 13),
                ),
              ),
            )
          else
            ..._scans.take(5).map(_buildScanTile),
        ],
      ),
    );
  }

  Widget _buildScanTile(ScanRecord scan) {
    final isIn = scan.direction == MovementDirection.inbound;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF1ED))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scan.barcode,
                  style: const TextStyle(
                    color: Color(0xFF294738),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${isIn ? 'From' : 'To'} ${scan.venue} · ${scan.reason}'
                  '${scan.personName.isEmpty ? '' : ' · ${scan.personName}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF68796E),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(scan.scannedAt),
                  style: const TextStyle(
                    color: Color(0xFF9BA99E),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: isIn ? const Color(0xFFE7F5D7) : const Color(0xFFFDF0DC),
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Text(
              scan.direction.label.toUpperCase(),
              style: TextStyle(
                color: isIn ? const Color(0xFF467B25) : const Color(0xFFAD712B),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF566E61),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    ),
  );

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} · $hour:$minute $period';
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5EBE4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x101C3A26),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow,
        style: const TextStyle(
          color: Color(0xFF6B9F58),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        title,
        style: const TextStyle(
          color: Color(0xFF172B2B),
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
    ],
  );
}
