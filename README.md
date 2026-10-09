# 📡 AirDiary

> A 100% free, serverless, privacy-first peer-to-peer tracking solution built using Flutter. AirDiary acts as a connectionless local logging diary, securely mapping the location history of your offline devices onto your phone using localized BLE beacon metrics.

### 📥 Pre-compiled App Downloads
[![Download for Android APK](https://img.shields.io/badge/Android-Download%20APK-red?style=for-the-badge&logo=android&logoColor=white)](#)
[![Download for iOS App](https://img.shields.io/badge/iOS-Download%20App-red?style=for-the-badge&logo=apple&logoColor=white)](#)
[![Download for Windows EXE](https://img.shields.io/badge/Windows-Download%20EXE-red?style=for-the-badge&logo=windows&logoColor=white)](#)
[![Download for macOS DMG](https://img.shields.io/badge/macOS-Download%20DMG-red?style=for-the-badge&logo=apple&logoColor=white)](#)

*(Note for users: Replace the '#' link paths with your actual repo release URLs once uploaded to GitHub)*

---

## 🔒 Core Philosophy: 100% Offline & Serverless

AirDiary was engineered from the ground up on the principle of **Zero-Knowledge Local-First Architecture**:
- **Zero Cloud Servers**: No accounts, no centralized databases, no analytics trackers, no telemetry.
- **Connectionless BLE Beacons**: Uses ambient Bluetooth Low Energy manufacturer broadcast packets (`0x01DA`) to announce device identities without establishing paired Bluetooth connections.
- **Local Persistence**: All tracked targets and location history logs reside strictly inside local on-device Hive storage boxes.
- **Hardware-Level Privacy**: Hardware GPS coordinate acquisition only executes locally when a registered peer signature is verified.

---

## 🛠️ How It Works

```
┌─────────────────────────┐                     ┌─────────────────────────┐
│     Target Device       │                     │    Monitoring Device    │
│  (Laptop, Phone, Beacon)│                     │     (Phone / Desktop)   │
└────────────┬────────────┘                     └────────────┬────────────┘
             │                                               │
   [1. Generates Self_ID]                           [1. Optical Pairing]
   (Cryptographic UUIDv4)                          (Scans QR / Types ID)
             │                                               │
   [2. Ambient BLE Broadcast]                                │
   (Raw 16-byte manufacturer data)                           │
             │                                               │
             │ ──────── BLE Advertisement Stream ──────────> │
             │                 (0x01DA)                      │
             │                                    [2. Passive BLE Scanner]
             │                                    (Decodes 16-byte UUID)
             │                                               │
             │                                    [3. Local Match & Filter]
             │                                    (Cross-references Box A)
             │                                               │
             │                                    [4. Throttle & Positioning]
             │                                    (5-min cooldown / GPS fix)
             │                                               │
             │                                    [5. Local DB Commit]
             │                                    (Saved to Box B: Logs)
```

### 1. Cryptographic Identity & Beacon Engine (`BroadcasterService`)
* Upon initial startup, each client device creates or loads a unique cryptographic `Self_ID` (UUIDv4) stored in local secure preferences.
* The device then broadcasts an ambient, connectionless BLE advertising packet with manufacturer ID `0x01DA` containing the 16 raw binary bytes of the `Self_ID`.
* Desktop fail-safe mechanisms gracefully detect OS kernel restrictions (such as on desktop platforms) and transition to passive tracking mode without throwing runtime exceptions.

### 2. Optical Zero-Server Pairing (`PairView`)
* Two devices can be paired in complete isolation without an internet connection or shared network.
* Device A displays a scannable high-contrast QR code generated directly from its `Self_ID`.
* Device B activates its camera sensor via `MobileScanner` to intercept the code. If camera hardware is absent (e.g., desktop workstations), a clean manual alphanumeric input form provides direct fallback.
* The paired target is committed to local storage **Box A (`TrackedDevices`)**.

### 3. Passive Background Scanner & Throttling (`ScannerService`)
* The monitoring device runs a continuous BLE scan using `FlutterBluePlus`.
* When an advertisement packet is intercepted, its manufacturer payload and service data are decoded to extract the UUID signature.
* If the signature matches a target registered in **Box A**, AirDiary initiates location resolution:
  * **Mobile (Android/iOS)**: Requests high-accuracy hardware GPS fixes via `Geolocator`.
  * **Desktop (Windows/macOS)**: Gracefully records `(0.0, 0.0)` stamped with a `Desktop Proximity Only` tag.
* A strict **5-minute cooldown timer per unique device ID** prevents database saturation and conserves battery and disk space.
* The record is written directly to **Box B (`LocationLogs`)**.

### 4. Local Analytics Dashboard & Deep-Linking (`DashboardView`)
* An adaptive UI grid scales responsively across phones, tablets, and wide desktop displays.
* Each card renders real-time status, last-seen timestamps calculated from local logs, and status badges.
* Clicking the **Map** button invokes native OS map engines via `url_launcher`:
  * **Android / Windows**: Deep-links to Google Maps (`https://www.google.com/maps/search/?api=1&query=lat,lng`).
  * **iOS / macOS**: Deep-links directly to Apple Maps (`https://maps.apple.com/?q=lat,lng`).

---

## 📂 Project Architecture

```
air_diary/
├── android/                   # Native Android manifests, permissions & Gradle
├── ios/                       # Native iOS Info.plist & background modes
├── macos/                     # Native macOS entitlements & permissions
├── windows/                   # Native Windows runner configurations
├── lib/
│   ├── main.dart              # App bootstrap & service initialization
│   ├── models/
│   │   ├── location_log.dart  # Box B schema (device_id, lat, lng, timestamp, tag)
│   │   └── tracked_device.dart# Box A schema (id, name, created_at)
│   ├── services/
│   │   ├── broadcaster_service.dart # BLE peripheral beacon transmitter
│   │   ├── scanner_service.dart     # Ambient BLE scanner & GPS logger
│   │   └── storage_service.dart     # 100% offline Hive database engine
│   └── views/
│       ├── dashboard_view.dart      # Adaptive dashboard & map launcher
│       └── pair_view.dart           # Offline QR pairing & camera scanner
├── pubspec.yaml               # Dependencies & asset manifests
└── README.md                  # Master documentation & download badges
```

---

## 🚀 Quick-Start & Development Setup

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.24.0 or newer)
* [Dart SDK](https://dart.dev/get-dart) (3.5.0 or newer)
* Android Studio / Xcode / VS Code with Flutter extensions

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/your-username/air_diary.git
cd air_diary
flutter pub get
```

### 2. Verify Code Quality & Static Analysis
```bash
flutter analyze
```

### 3. Run the Application
#### Android / iOS
```bash
flutter run
```

#### macOS Desktop
```bash
flutter run -d macos
```

#### Windows Desktop
```bash
flutter run -d windows
```

---

## 📋 Platform Privacy Configuration

| Platform | Permission / Entitlement | Purpose |
| :--- | :--- | :--- |
| **Android** | `ACCESS_FINE_LOCATION` | Captures GPS coordinates for local diary logs |
| **Android** | `BLUETOOTH_SCAN` / `ADVERTISE` | Broadcasts & listens for offline BLE beacon packets |
| **Android** | `CAMERA` | Scans offline QR codes for device pairing |
| **iOS** | `NSBluetoothAlwaysUsageDescription` | Ambient peer beacon discovery |
| **iOS** | `NSLocationWhenInUseUsageDescription` | Local GPS location logging |
| **iOS** | `NSCameraUsageDescription` | Optical device synchronization |
| **macOS** | `com.apple.security.device.bluetooth` | Hardware BLE communication |
| **macOS** | `com.apple.security.personal-information.location` | Offline proximity coordinate logging |

---

## ⚖️ License
AirDiary is released under the **MIT Open Source License**. 100% free, private, and open for personal and community use.
# AirDiary
# AirDiary
