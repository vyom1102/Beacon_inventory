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

Allow camera access when prompted. On iPhone, the device must be paired with a Mac running Xcode.

## Build an installable package

```sh
flutter build apk
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`. For iOS, open `ios/Runner.xcworkspace` in Xcode, select a signing team, then build and install on a connected iPhone.

The dashboard groups the latest beacon state by venue. Tap a venue to see its beacons and a beacon to view movements from the past three months (or its last older movement). The app scans Bluetooth advertisements while open and labels a beacon Active after a matching recent sighting. If a beacon advertises a device ID rather than its barcode, enter that Bluetooth ID with a movement.

To share inventory across devices, deploy the companion API in `backend-navigation`. Its inventory endpoints are public and the app sends no API key. The default API URL is `https://maps.iwayplus.in/api/beacon-inventory`; use `--dart-define=BEACON_API_URL=...` to change it. Existing local scan history is not uploaded automatically.
# Beacon_inventory
