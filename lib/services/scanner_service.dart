import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/location_log.dart';
import '../models/tracked_device.dart';
import 'anti_stalking_service.dart';
import 'storage_service.dart';

/// Event model representing a live BLE detection event for historical database logging
class ScanDetectionEvent {
  final TrackedDevice device;
  final LocationLog log;
  final int rssi;
  final DateTime detectedAt;

  ScanDetectionEvent({
    required this.device,
    required this.log,
    required this.rssi,
    required this.detectedAt,
  });
}

/// Real-time live RSSI event for high-frequency signal radar and hot/cold precision finding
class LiveRssiEvent {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final DateTime timestamp;

  LiveRssiEvent({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.timestamp,
  });
}

/// Passive Background Scanner & Location Logger.
/// Continuously scans ambient BLE signatures, decodes AirDiary manufacturer data,
/// cross-references against locally registered TrackedDevices, throttles entries
/// via a strict 5-minute cooldown per device, emits unthrottled live RSSI streams for
/// real-time radar finding, and feeds un-tracked ambient beacons into the Anti-Stalking engine.
class ScannerService extends ChangeNotifier {
  static final ScannerService _instance = ScannerService._internal();
  factory ScannerService() => _instance;
  ScannerService._internal();

  final StorageService _storageService = StorageService();
  final AntiStalkingService _antiStalkingService = AntiStalkingService();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String _statusMessage = 'Scanner ready (Standby)';
  String get statusMessage => _statusMessage;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  // Strict 5-minute cooldown timer mapped per unique device ID for DB writing
  final Map<String, DateTime> _deviceCooldownMap = {};

  // Stream of periodic detection events for UI notifications and DB logging
  final StreamController<ScanDetectionEvent> _detectionController =
      StreamController<ScanDetectionEvent>.broadcast();
  Stream<ScanDetectionEvent> get detectionStream => _detectionController.stream;

  // Stream of unthrottled live RSSI updates for real-time Radar / Precision Finding
  final StreamController<LiveRssiEvent> _liveRssiController =
      StreamController<LiveRssiEvent>.broadcast();
  Stream<LiveRssiEvent> get liveRssiStream => _liveRssiController.stream;

  ScanDetectionEvent? _lastDetection;
  ScanDetectionEvent? get lastDetection => _lastDetection;

  int _totalScannedPackets = 0;
  int get totalScannedPackets => _totalScannedPackets;

  /// Initialize the scanner service and hook into Bluetooth lifecycle
  Future<void> init() async {
    try {
      if (!_storageService.isInitialized) {
        await _storageService.init();
      }

      // Listen for hardware scan state changes
      _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
        _isScanning = scanning;
        notifyListeners();
      });

      _statusMessage = 'Scanner initialized & ready';
      debugPrint('[ScannerService] Initialized successfully');
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Scanner init exception: $e';
      debugPrint('[ScannerService] Init Exception (Safely Intercepted): $e');
      notifyListeners();
    }
  }

  /// Start continuous ambient BLE scanning
  Future<bool> startScanning() async {
    try {
      // Ensure Bluetooth is available and powered on
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) {
        _statusMessage = 'BLE hardware unsupported on this system';
        debugPrint('[ScannerService] BLE not supported');
        notifyListeners();
        return false;
      }

      // Check adapter state on mobile
      if (Platform.isAndroid || Platform.isIOS) {
        final adapterState = await FlutterBluePlus.adapterState.first;
        if (adapterState != BluetoothAdapterState.on) {
          _statusMessage = 'Bluetooth is turned OFF. Please enable Bluetooth.';
          debugPrint('[ScannerService] Bluetooth adapter is not ON: $adapterState');
          notifyListeners();
          return false;
        }
      }

      // Cancel any existing subscription
      await _scanSubscription?.cancel();

      // Listen to scan results stream
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        _processScanResults,
        onError: (err) {
          _statusMessage = 'Scan stream error: $err';
          debugPrint('[ScannerService] Scan stream error: $err');
          notifyListeners();
        },
      );

      // Spin up scanning with battery-optimized parameters
      await FlutterBluePlus.startScan(
        timeout: null, // continuous background scan stream
        androidUsesFineLocation: true,
      );

      _isScanning = true;
      _statusMessage = 'Passively monitoring ambient BLE beacons...';
      debugPrint('[ScannerService] Continuous ambient scanning started');
      notifyListeners();
      return true;
    } on PlatformException catch (e) {
      _isScanning = false;
      _statusMessage = 'Platform scan exception: ${e.message ?? e.code}';
      debugPrint('[ScannerService] PlatformException: $e');
      notifyListeners();
      return false;
    } catch (e) {
      _isScanning = false;
      _statusMessage = 'Scanner error: $e';
      debugPrint('[ScannerService] Generic exception: $e');
      notifyListeners();
      return false;
    }
  }

  /// Process incoming ambient BLE advertisement packets
  void _processScanResults(List<ScanResult> results) {
    _totalScannedPackets += results.length;

    for (final result in results) {
      try {
        final candidates = _extractCandidateSignatures(result);
        if (candidates.isEmpty) continue;

        // Cross-reference detected candidates against local TrackedDevices
        final trackedDevice = _findTrackedDevice(candidates);
        if (trackedDevice != null) {
          // 1. Emit live unthrottled RSSI update for real-time Radar / Hot-Cold UI
          _liveRssiController.add(
            LiveRssiEvent(
              deviceId: trackedDevice.id,
              deviceName: trackedDevice.name,
              rssi: result.rssi,
              timestamp: DateTime.now(),
            ),
          );

          // 2. Handle throttled database persistence
          _handleTrackedMatch(trackedDevice, result.rssi);
        } else {
          // Forward un-paired ambient signatures into Anti-Stalking engine
          final primarySignature = candidates.first;
          _antiStalkingService.processAmbientSighting(primarySignature, result.rssi);
        }
      } catch (e) {
        debugPrint('[ScannerService] Error parsing scan result: $e');
      }
    }
  }

  /// Extracts all potential device signatures, UUIDs, and MAC addresses from raw BLE advertisement data
  Set<String> _extractCandidateSignatures(ScanResult result) {
    final candidates = <String>{};
    final adv = result.advertisementData;

    // 1. Physical / Virtual Remote Hardware ID (MAC address / CoreBluetooth UUID)
    final remoteId = result.device.remoteId.str.trim();
    if (remoteId.isNotEmpty) {
      candidates.add(remoteId.toLowerCase());
      candidates.add(remoteId.replaceAll(':', '').replaceAll('-', '').toLowerCase());
    }

    // 2. Advertised & Platform Local Names
    if (adv.advName.trim().isNotEmpty) {
      candidates.add(adv.advName.trim().toLowerCase());
    }
    if (result.device.platformName.trim().isNotEmpty) {
      candidates.add(result.device.platformName.trim().toLowerCase());
    }

    // 3. Manufacturer Specific Data (AirDiary: 0x01DA, Apple/iBeacon: 0x004C, AltBeacon, etc.)
    for (final entry in adv.manufacturerData.entries) {
      final dataBytes = entry.value;
      if (dataBytes.length >= 16) {
        try {
          final uuidCandidate = Uuid.unparse(dataBytes.sublist(0, 16)).toLowerCase();
          candidates.add(uuidCandidate);
          candidates.add(uuidCandidate.replaceAll('-', ''));
        } catch (_) {}
      }
      // Hex representation of first 8-16 bytes
      if (dataBytes.isNotEmpty) {
        final hexStr = dataBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toLowerCase();
        candidates.add(hexStr);
      }
    }

    // 4. Service UUIDs
    for (final serviceGuid in adv.serviceUuids) {
      final str128 = serviceGuid.str128.toLowerCase();
      candidates.add(str128);
      candidates.add(str128.replaceAll('-', ''));
      final str = serviceGuid.str.toLowerCase();
      candidates.add(str);
    }

    // 5. Service Data Payload
    for (final entry in adv.serviceData.entries) {
      if (entry.value.length >= 16) {
        try {
          final serviceDataUuid = Uuid.unparse(entry.value.sublist(0, 16)).toLowerCase();
          candidates.add(serviceDataUuid);
        } catch (_) {}
      }
    }

    return candidates;
  }

  /// Cross-reference candidate signatures against local TrackedDevices box
  TrackedDevice? _findTrackedDevice(Set<String> candidateSignatures) {
    final devices = _storageService.getTrackedDevices();

    for (final device in devices) {
      final deviceId = device.id.trim().toLowerCase();
      final deviceIdClean = deviceId.replaceAll(':', '').replaceAll('-', '');
      final deviceName = device.name.trim().toLowerCase();

      for (final candidate in candidateSignatures) {
        final candidateClean = candidate.replaceAll(':', '').replaceAll('-', '');
        if (candidate == deviceId ||
            candidateClean == deviceIdClean ||
            candidate == deviceName) {
          return device;
        }
      }
    }
    return null;
  }

  /// Handle detected match: throttle control, platform positioning divergence, and DB logging
  Future<void> _handleTrackedMatch(TrackedDevice device, int rssi) async {
    final now = DateTime.now();

    // Strict 5-Minute Throttle Control per Unique Device ID for database writes
    final lastLogged = _deviceCooldownMap[device.id];
    if (lastLogged != null && now.difference(lastLogged) < const Duration(minutes: 5)) {
      return;
    }

    debugPrint('[ScannerService] MATCH RECORDED: ${device.name} (${device.id}) @ RSSI: $rssi dBm');

    // Platform-Divergent Positioning Mechanics
    double latitude = 0.0;
    double longitude = 0.0;
    String tag = 'GPS Hardware Fix';

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 10),
            ),
          );
          latitude = position.latitude;
          longitude = position.longitude;
          tag = 'Mobile GPS Location';
        } else {
          latitude = 0.0;
          longitude = 0.0;
          tag = 'Location Permission Denied';
        }
      } catch (e) {
        debugPrint('[ScannerService] GPS acquisition error: $e');
        latitude = 0.0;
        longitude = 0.0;
        tag = 'GPS Sensor Fallback';
      }
    } else {
      // Desktop Environments (Windows/macOS) without accessible GPS chips
      latitude = 0.0;
      longitude = 0.0;
      tag = 'Desktop Proximity Only';
    }

    // Write new record to local LocationLogs box
    final log = LocationLog(
      deviceId: device.id,
      latitude: latitude,
      longitude: longitude,
      timestamp: now,
      tag: tag,
    );

    await _storageService.saveLocationLog(log);

    // Commit cooldown timestamp
    _deviceCooldownMap[device.id] = now;

    // Surface detection event
    final event = ScanDetectionEvent(
      device: device,
      log: log,
      rssi: rssi,
      detectedAt: now,
    );
    _lastDetection = event;
    _detectionController.add(event);

    _statusMessage = 'Proximity match recorded: ${device.name} at ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    notifyListeners();
  }

  /// Manually trigger a mock proximity event (useful for verification and desktop debugging)
  Future<void> simulateProximityEvent(TrackedDevice device) async {
    await _handleTrackedMatch(device, -65);
    _liveRssiController.add(
      LiveRssiEvent(
        deviceId: device.id,
        deviceName: device.name,
        rssi: -65,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Simulate a live RSSI fluctuation for Precision Finding testing
  void simulateLiveRssi(String deviceId, String deviceName, int rssi) {
    _liveRssiController.add(
      LiveRssiEvent(
        deviceId: deviceId,
        deviceName: deviceName,
        rssi: rssi,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Stop continuous BLE scanning
  Future<void> stopScanning() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      _isScanning = false;
      _statusMessage = 'Scanner stopped (Standby)';
      debugPrint('[ScannerService] Scanning stopped');
      notifyListeners();
    } catch (e) {
      _isScanning = false;
      _statusMessage = 'Scanner stop notice: $e';
      debugPrint('[ScannerService] Stop notice: $e');
      notifyListeners();
    }
  }

  /// Toggle scanning on/off
  Future<void> toggleScanning() async {
    if (_isScanning) {
      await stopScanning();
    } else {
      await startScanning();
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _detectionController.close();
    _liveRssiController.close();
    super.dispose();
  }
}
