# Beacon Inventory

A native Flutter app for recording beacon movements on Android and iOS. The app scans Code 128, Code 39, and Code 93 barcodes with a camera scan window tuned for faster beacon reads, including identifiers such as `IW25030199`. Movement history is stored in a local SQLite database on the device.

Each scan records its barcode, In/Out status, source or destination venue, responsible person's name, reason, optional reference and remarks, and timestamp. In and Out have the same reason choices as the linked inventory form, with an Other field for a custom reason. Repeating the same status for a beacon is blocked. Export the scan history as an Excel spreadsheet through the device's share sheet.

## Requirements

- Flutter SDK
- Android Studio / Android SDK for Android builds
- Xcode on macOS for iPhone builds

## Run on a connected device

```sh
flutter pub get
flutter devices
flutter run
```

Allow camera, Bluetooth, and (on Android) location access when prompted, and keep Bluetooth enabled. The camera scanner uses only the camera. Press **Barcode not visible? Show nearby beacons** to open a Bluetooth-only page; continuous BLE scanning runs while that page is open. It shows advertised beacon names at RSSI −50 dBm or stronger; tap a suggestion to use its name as the barcode and fill its Bluetooth ID. The movement form runs a five-second Bluetooth scan when it opens and every minute while it remains visible. The **Check Bluetooth once** button starts another five-second check on demand. Scanning stops before the camera opens. A detected signal confirms the beacon is advertising; zero devices or a missing match does not by itself prove that the beacon is faulty. On iPhone, the device must be paired with a Mac running Xcode.

## Build an installable package

```sh
flutter build apk
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. For iOS, open `ios/Runner.xcworkspace` in Xcode, select a signing team, then build and install on a connected iPhone.

The dashboard groups the latest beacon state by venue. Tap a venue to see its beacons and a beacon to view movements from the past three months (or its last older movement). The app labels a beacon Active after a matching recent sighting. If a beacon advertises a device ID rather than its barcode, enter that Bluetooth ID with a movement.

Saving a movement uses the latest BLE results and sends its active/not-detected result to the inventory API. If no recent Bluetooth scan exists, the status is unknown; saving does not start a scan. Battery voltage is decoded from the first byte of manufacturer data, matching `localization_engine`, with the older InPlay packet layout as a fallback. The app shows and sends an estimated battery percentage when a valid voltage is available. Other packets leave battery unknown. The percentage uses a simple 2.0–3.0 V estimate because a manufacturer battery discharge curve is not available; it should not be treated as an exact charge reading.

To share inventory across devices, deploy the companion API in `backend-navigation`. Its inventory endpoints are public and the app sends no API key. The default API URL is `https://maps.iwayplus.in/api/beacon-inventory`; use `--dart-define=BEACON_API_URL=...` to change it. Existing local scan history is not uploaded automatically.
# Beacon_inventory
