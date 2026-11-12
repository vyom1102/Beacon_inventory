import 'dart:async';

import 'package:flutter/material.dart';

import 'beacon_presence.dart';

class NearbyBeaconPage extends StatefulWidget {
  const NearbyBeaconPage({super.key});

  @override
  State<NearbyBeaconPage> createState() => _NearbyBeaconPageState();
}

class _NearbyBeaconPageState extends State<NearbyBeaconPage>
    with WidgetsBindingObserver {
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    BeaconPresence.instance.start();
    _refresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BeaconPresence.instance.start();
    } else if (state == AppLifecycleState.paused) {
      BeaconPresence.instance.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refresh?.cancel();
    BeaconPresence.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Find beacon')),
    body: AnimatedBuilder(
      animation: BeaconPresence.instance,
      builder: (context, _) {
        final presence = BeaconPresence.instance;
        final suggestions = presence.suggestions;
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'If the barcode is unreadable, select the beacon name below.',
              ),
            ),
            if (presence.scanError != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  presence.scanError!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Expanded(
              child: suggestions.isEmpty
                  ? const Center(child: Text('Looking for your beacon…'))
                  : ListView.builder(
                      itemCount: suggestions.length,
                      itemBuilder: (context, index) {
                        final beacon = suggestions[index];
                        return ListTile(
                          leading: const Icon(Icons.bluetooth_searching),
                          title: Text(beacon.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(beacon),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
