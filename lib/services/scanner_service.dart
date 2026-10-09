import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../models/location_log.dart';
import '../models/tracked_device.dart';
import 'broadcaster_service.dart';
import 'storage_service.dart';

/// Event model representing a live BLE detection event
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

/// Passive Background Scanner & Location Logger.
/// Continuously scans ambient BLE signatures, decodes AirDiary manufacturer data,
/// cross-references against locally registered TrackedDevices, throttles entries
/// via a strict 5-minute cooldown per device, and performs platform-divergent
/// location acquisition (Hardware GPS on mobile vs (0.0, 0.0) on desktop).
class ScannerService extends ChangeNotifier {
  static final ScannerService _instance = ScannerService._internal();
  factory ScannerService() => _instance;
  ScannerService._internal();

  final StorageService _storageService = StorageService();

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  String _statusMessage = 'Scanner ready (Standby)';
  String get statusMessage => _statusMessage;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;

  // Strict 5-minute cooldown timer mapped per unique device ID
  final Map<String, DateTime> _deviceCooldownMap = {};

  // Stream of real-time detection events for UI notifications
  final StreamController<ScanDetectionEvent> _detectionController =
      StreamController<ScanDetectionEvent>.broadcast();
  Stream<ScanDetectionEvent> get detectionStream => _detectionController.stream;

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
        final detectedId = _extractSignatureId(result);
        if (detectedId == null) continue;

        // Cross-reference detected ID against local TrackedDevices
        final trackedDevice = _findTrackedDevice(detectedId);
        if (trackedDevice != null) {
          _handleTrackedMatch(trackedDevice, result.rssi);
        }
      } catch (e) {
        debugPrint('[ScannerService] Error parsing scan result: $e');
      }
    }
  }

  /// Extracts the potential device UUID signature from raw BLE advertisement data
  String? _extractSignatureId(ScanResult result) {
    final adv = result.advertisementData;

    // 1. Check Manufacturer Specific Data (AirDiary Protocol)
    for (final entry in adv.manufacturerData.entries) {
      final dataBytes = entry.value;
      if (dataBytes.length >= 16) {
        try {
          final uuidCandidate = Uuid.unparse(dataBytes.sublist(0, 16)).toLowerCase();
          return uuidCandidate;
        } catch (_) {}
      }
    }

    // 2. Check Service UUIDs
    for (final serviceGuid in adv.serviceUuids) {
      final guidStr = serviceGuid.str128.toLowerCase();
      if (guidStr != BroadcasterService.airDiaryServiceUuid.toLowerCase()) {
        return guidStr;
      }
    }

    // 3. Check Service Data payload
    for (final entry in adv.serviceData.entries) {
      if (entry.value.length >= 16) {
        try {
          return Uuid.unparse(entry.value.sublist(0, 16)).toLowerCase();
        } catch (_) {}
      }
    }

    return null;
  }

  /// Cross-reference signature against local TrackedDevices box
  TrackedDevice? _findTrackedDevice(String signatureId) {
    final normalized = signatureId.trim().toLowerCase();
    final devices = _storageService.getTrackedDevices();

    for (final device in devices) {
      if (device.id.trim().toLowerCase() == normalized) {
        return device;
      }
    }
    return null;
  }

  /// Handle detected match: throttle control, platform positioning divergence, and DB logging
  Future<void> _handleTrackedMatch(TrackedDevice device, int rssi) async {
    final now = DateTime.now();

    // Strict 5-Minute Throttle Control per Unique Device ID
    final lastLogged = _deviceCooldownMap[device.id];
    if (lastLogged != null && now.difference(lastLogged) < const Duration(minutes: 5)) {
      debugPrint('[ScannerService] Throttled match for ${device.name} (Cooldown active: ${5 - now.difference(lastLogged).inMinutes}m remaining)');
      return;
    }

    debugPrint('[ScannerService] MATCH DETECTED: ${device.name} (${device.id}) @ RSSI: $rssi dBm');

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
    super.dispose();
  }
}
