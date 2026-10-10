# 📡 AirDiary

> A 100% free, serverless, privacy-first peer-to-peer tracking and personal safety suite built using Flutter. AirDiary acts as a connectionless local logging diary and real-time security radar, securely mapping the location history and proximity of your offline devices onto your phone using localized BLE beacon metrics, zero-cloud LAN P2P synchronization, geofenced safe zones, and anti-stalking rogue beacon heuristics.

### 📥 Pre-compiled App Downloads
[![Download for Android APK](https://img.shields.io/badge/Android-Download%20APK-red?style=for-the-badge&logo=android&logoColor=white)](https://github.com/AritranexX/AirDiary/releases/latest/download/AirDiary-android.apk)
[![Download for iOS App](https://img.shields.io/badge/iOS-Download%20App-red?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/AritranexX/AirDiary/releases/latest/download/AirDiary-ios.ipa)
[![Download for Windows EXE](https://img.shields.io/badge/Windows-Download%20EXE-red?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/AritranexX/AirDiary/releases/latest/download/AirDiary-windows.zip)
[![Download for macOS DMG](https://img.shields.io/badge/macOS-Download%20DMG-red?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/AritranexX/AirDiary/releases/latest/download/AirDiary-macos.dmg)

> Direct repository release downloads: [GitHub Releases — AirDiary](https://github.com/AritranexX/AirDiary/releases)

---

## 🔒 Core Philosophy: 100% Offline & $0 Serverless

AirDiary was engineered from the ground up on the principle of **Zero-Knowledge Local-First Architecture**:
- **Zero Cloud Servers & Zero Cost ($0)**: No subscription fees, no accounts, no centralized databases, no analytics trackers, no telemetry.
- **Connectionless BLE Beacons**: Uses ambient Bluetooth Low Energy manufacturer broadcast packets (`0x01DA`) to announce device identities without establishing paired Bluetooth connections.
- **Local Isolated Persistence**: All tracked targets, safe zones, rogue beacon detections, and location history logs reside strictly inside local on-device Hive storage boxes.
- **Direct LAN P2P Socket Sync**: Synchronizes diaries across your personal laptops and phones via local Wi-Fi UDP discovery & direct TCP streams without ever touching the Internet.
- **Hardware-Level Privacy**: Hardware GPS coordinate acquisition only executes locally when a registered peer signature is verified.

---

## 🛡️ 5 Advanced $0 Local-Only Privacy Capabilities

### 1. 🎯 Real-Time RSSI Signal Radar & Hot/Cold Precision Finder
* **Real-Time Sweep Radar**: Interactive radar sweep UI rendering live signal strength and proximity zones (Immediate `<1m`, Near `1-4m`, Far `>4m`, Out of Range).
* **Exponential Weighted Moving Average (EWMA) Filter**: Mathematically cleans raw BLE RSSI flutter:
  $$\text{smoothedRSSI}_t = (\alpha \cdot \text{rawRSSI}_t) + ((1.0 - \alpha) \cdot \text{smoothedRSSI}_{t-1}) \quad (\alpha = 0.35)$$
* **Log-Distance Path Loss Model**: Estimates real-time physical distance using calibrated TxPower:
  $$\text{Distance} = 10^{\frac{\text{TxPower} - \text{smoothedRSSI}}{10 \cdot n}} \quad (\text{TxPower} = -59\text{ dBm}, n = 2.2)$$

### 2. 📍 Left-Behind Smart Separation Alerts & Geofenced Safe Zones
* **Geofenced Safe Zones**: Designate personal sanctuary zones (Home, Office, Gym) with customizable geofence radius.
* **Haversine Geodesic Distance Math**: Automatically detects when the user departs a safe zone:
  $$d = 2R \cdot \arcsin\left(\sqrt{\sin^2\left(\frac{\Delta\phi}{2}\right) + \cos(\phi_1)\cos(\phi_2)\sin^2\left(\frac{\Delta\lambda}{2}\right)}\right)$$
* **Smart Separation Heuristic**: Triggers left-behind alerts only when a tracked belonging is absent for $\ge 15$ minutes while outside all designated safe zones, preventing false alarms at home.

### 3. 🚨 Anti-Stalking Shield & Rogue Beacon Detection
* **Un-paired Beacon Tracking**: Passively monitors ambient BLE beacons without connecting to them.
* **Multi-Cluster Spatial Heuristic**: Analyzes unknown beacon sightings across space and time.
* **Suspicious Route Flagging**: If an un-paired beacon is observed traveling with you across $\ge 2$ distinct geographic clusters ($>150\text{m}$ apart) over $\ge 15$ minutes, AirDiary immediately alerts you of potential rogue tracking.

### 4. 🔄 Zero-Cloud Local LAN Direct Socket P2P Sync
* **Zero-Configuration UDP Discovery**: Discovers peer AirDiary instances on the same Wi-Fi subnet using port `41820` broadcast (`AIRDIARY_DISCOVERY_PING:<selfId>:<deviceName>:41820`).
* **Direct Socket Delta Exchange**: Establishes secure peer-to-peer TCP streams to sync tracked devices and location diaries across laptops, desktops, and phones.
* **100% Offline Multi-Device Ecosystem**: Share location logs and device lists between your MacBook and Android phone without any third-party cloud.

### 5. 🗺️ Historical Breadcrumb Timeline & One-Tap Map Deep-Linking
* **Chronological Diary**: Organized log timeline grouped by date, showing signal metrics, timestamps, and proximity tags.
* **Trip Path Visualization**: Track movement history and breadcrumb routes per belonging.
* **Native Map Launch**: Direct one-tap deep-linking into Apple Maps (macOS / iOS) or Google Maps (Android / Windows).

---

## 🛠️ How Core BLE Proximity Works

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

---

## 📂 Project Architecture

```
air_diary/
├── android/                   # Native Android manifests, permissions & Gradle 8.14.0
├── ios/                       # Native iOS Info.plist & background modes
├── macos/                     # Native macOS entitlements & permissions
├── windows/                   # Native Windows runner configurations
├── lib/
│   ├── main.dart              # App bootstrap & multi-service initialization
│   ├── models/
│   │   ├── lan_peer.dart      # LAN P2P peer model
│   │   ├── location_log.dart  # Box B schema (device_id, lat, lng, timestamp, tag)
│   │   ├── rogue_beacon.dart  # Box D schema (signature, sightings, clusters)
│   │   ├── safe_zone.dart     # Box C schema (geofence radius, haversine math)
│   │   └── tracked_device.dart# Box A schema (id, name, created_at)
│   ├── services/
│   │   ├── anti_stalking_service.dart # Spatial clustering & rogue beacon detection
│   │   ├── broadcaster_service.dart   # BLE peripheral beacon transmitter
│   │   ├── lan_sync_service.dart      # UDP discovery & TCP socket P2P sync
│   │   ├── scanner_service.dart       # Ambient BLE scanner & unthrottled RSSI stream
│   │   ├── separation_service.dart    # Left-behind separation alert engine
│   │   ├── storage_service.dart       # 100% offline Hive database engine (Boxes A-E)
│   │   └── update_service.dart        # In-app GitHub release update & platform asset matcher
│   └── views/
│       ├── anti_stalking_view.dart    # Rogue beacon security shield & audit
│       ├── dashboard_view.dart        # 5-tab main view with alert banners
│       ├── lan_sync_view.dart         # Local LAN peer discovery & sync UI
│       ├── pair_view.dart             # Offline QR pairing & camera scanner
│       ├── radar_view.dart            # Real-time RSSI signal radar & distance gauge
│       ├── safe_zones_view.dart       # Geofenced sanctuary zone manager
│       └── timeline_view.dart         # Chronological breadcrumb history
├── test/
│   ├── models_test.dart       # Serialization & mathematical verification tests
│   └── services_test.dart     # EWMA, Haversine, LAN protocol & anti-stalking tests
├── pubspec.yaml               # Dependencies & asset manifests (v1.2.0+3)
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
git clone https://github.com/AritranexX/AirDiary.git
cd AirDiary
flutter pub get
```

### 2. Verify Code Quality & Static Analysis
```bash
flutter analyze
flutter test
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
| **Android** | `ACCESS_FINE_LOCATION` | Captures GPS coordinates for local diary logs & safe zones |
| **Android** | `BLUETOOTH_SCAN` / `ADVERTISE` | Broadcasts & listens for offline BLE beacon packets |
| **Android** | `CAMERA` | Scans offline QR codes for device pairing |
| **Android** | `INTERNET` / `ACCESS_WIFI_STATE` | Local subnet LAN P2P socket discovery (port 41820) |
| **iOS** | `NSBluetoothAlwaysUsageDescription` | Ambient peer beacon discovery & broadcast |
| **iOS** | `NSLocationWhenInUseUsageDescription` | Local GPS location logging & geofencing |
| **iOS** | `NSCameraUsageDescription` | Optical device synchronization |
| **macOS** | `com.apple.security.device.bluetooth` | Hardware BLE communication |
| **macOS** | `com.apple.security.personal-information.location` | Offline proximity coordinate logging |
| **macOS / Windows** | `com.apple.security.network.server` / `client` | Local LAN peer socket synchronization |

---

## ⚖️ License
AirDiary is released under the **MIT Open Source License**. 100% free, private, and open for personal and community use.
