# Beacon Inventory

A native Flutter app for recording beacon movements on Android and iOS. The app scans barcodes with the phone camera, including Code 128 and Code 39 identifiers such as `IW25030199`, and stores movement history in a local SQLite database on the device.

Each scan records its barcode, In/Out status, venue, reason, and timestamp. Repeating the same status for a beacon is blocked. Export the scan history as an Excel spreadsheet through the device's share sheet.

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

Scan history is stored locally on each device; it is not synchronized to a server. Export and share a spreadsheet to move scan data to another device.
# Beacon_inventory
