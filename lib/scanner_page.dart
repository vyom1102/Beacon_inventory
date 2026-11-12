import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _returnedBarcode = false;

  void _onDetect(BarcodeCapture capture) {
    if (_returnedBarcode) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _returnedBarcode = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF102D2B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102D2B),
        foregroundColor: Colors.white,
        title: const Text('Scan beacon'),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                final scanWindow = Rect.fromCenter(
                  center: size.center(Offset.zero),
                  width: size.width * 0.9,
                  height: size.height * 0.32,
                );
                return Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    MobileScanner(
                      onDetect: _onDetect,
                      onDetectError: (error, stackTrace) {
                        debugPrint('Barcode detection error: $error');
                      },
                      errorBuilder: (context, error) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Camera could not start: ${error.errorCode.name}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                              if (error.errorDetails?.message != null)
                                Text(
                                  error.errorDetails!.message!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              const SizedBox(height: 8),
                              const Text(
                                'Check camera permission in phone Settings, then reopen this screen.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ),
                      placeholderBuilder: (_) => const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFB8EA68),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: scanWindow.width,
                          height: scanWindow.height,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFB8EA68),
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 18, 24, 30),
            child: Column(
              children: [
                Icon(Icons.center_focus_strong, color: Color(0xFFB8EA68)),
                SizedBox(height: 8),
                Text(
                  'Point the camera at the barcode',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'If the barcode is not visible, go back and choose Show nearby beacons.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFB4C7BC), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
