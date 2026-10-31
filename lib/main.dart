import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'inventory_store.dart';
import 'scanner_page.dart';

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

class _InventoryPageState extends State<InventoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _venueController = TextEditingController();
  final _reasonController = TextEditingController();
  final _barcodeController = TextEditingController();

  List<ScanRecord> _scans = [];
  MovementDirection _direction = MovementDirection.inbound;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;

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
    _loadScans();
  }

  @override
  void dispose() {
    _venueController.dispose();
    _reasonController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadScans() async {
    try {
      final scans = await InventoryStore.instance.getScans();
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
    final barcode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ScannerPage()),
    );
    if (!mounted || barcode == null) return;
    setState(() => _barcodeController.text = barcode);
  }

  Future<void> _saveScan() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      await InventoryStore.instance.saveScan(
        barcode: _barcodeController.text.trim(),
        venue: _venueController.text.trim(),
        reason: _reasonController.text.trim(),
        direction: _direction,
      );
      _barcodeController.clear();
      await _loadScans();
      if (!mounted) return;
      _showMessage(
        '${_scans.isEmpty ? 'Beacon' : 'Scan'} recorded successfully.',
      );
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
        TextCellValue('Reason'),
      ]);
      for (final scan in _scans.reversed) {
        sheet.appendRow([
          TextCellValue(scan.scannedAt.toUtc().toIso8601String()),
          TextCellValue(scan.barcode),
          TextCellValue(scan.direction.label.toUpperCase()),
          TextCellValue(scan.venue),
          TextCellValue(scan.reason),
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
    final latest = _latestByBarcode.values;
    final currentIn = latest
        .where((scan) => scan.direction == MovementDirection.inbound)
        .length;
    final currentOut = latest
        .where((scan) => scan.direction == MovementDirection.outbound)
        .length;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadScans,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 22),
              _buildStats(
                total: latest.length,
                inCount: currentIn,
                outCount: currentOut,
                movements: _scans.length,
              ),
              const SizedBox(height: 18),
              _buildScanCard(),
              const SizedBox(height: 18),
              _buildRecentScans(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _forest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.radar_rounded, color: _lime, size: 28),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BEACON / INVENTORY',
                style: TextStyle(
                  color: Color(0xFF6B9F58),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Beacon scanner',
                style: TextStyle(
                  color: Color(0xFF172B2B),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          onPressed: _exportScans,
          tooltip: 'Export scan history',
          icon: const Icon(Icons.file_download_outlined),
        ),
      ],
    );
  }

  Widget _buildStats({
    required int total,
    required int inCount,
    required int outCount,
    required int movements,
  }) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.72,
      children: [
        _StatCard(label: 'Total beacons', value: total, icon: Icons.qr_code_2),
        _StatCard(
          label: 'Currently in',
          value: inCount,
          icon: Icons.south_west_rounded,
        ),
        _StatCard(
          label: 'Currently out',
          value: outCount,
          icon: Icons.north_east_rounded,
        ),
        _StatCard(
          label: 'Movements logged',
          value: movements,
          icon: Icons.swap_horiz_rounded,
        ),
      ],
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
            title: 'Scan a beacon',
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
            onSelectionChanged: (selection) =>
                setState(() => _direction = selection.first),
          ),
          const SizedBox(height: 18),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('VENUE NAME'),
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
                _fieldLabel('REASON'),
                TextFormField(
                  controller: _reasonController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Returned from event',
                    counterText: '',
                  ),
                  validator: (value) => _required(value, 'Enter a reason.'),
                ),
                const SizedBox(height: 14),
                _fieldLabel('BEACON BARCODE'),
                TextFormField(
                  controller: _barcodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 150,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. IW25030199',
                    counterText: '',
                    suffixIcon: IconButton(
                      onPressed: _openScanner,
                      tooltip: 'Open camera scanner',
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                  validator: (value) =>
                      _required(value, 'Scan or enter a barcode.'),
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
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Camera scan or enter the barcode manually',
              style: TextStyle(color: Color(0xFF87968B), fontSize: 11),
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
            ..._scans.take(30).map(_buildScanTile),
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
                  '${scan.venue} · ${scan.reason}',
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

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5EBE4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: const Color(0xFF78916F)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF82918A), fontSize: 11),
              ),
            ),
          ],
        ),
        Text(
          '$value',
          style: const TextStyle(
            color: Color(0xFF172B2B),
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
      ],
    ),
  );
}
