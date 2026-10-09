import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/tracked_device.dart';
import '../models/location_log.dart';

/// Local-First Storage Service powered by Hive.
/// Manages Box A (TrackedDevices) and Box B (LocationLogs) strictly on local storage
/// with zero outward network calls.
class StorageService extends ChangeNotifier {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  static const String boxTrackedDevices = 'TrackedDevices';
  static const String boxLocationLogs = 'LocationLogs';
  static const String boxAppSettings = 'AppSettings';
  static const String keySelfId = 'Self_ID';

  late Box<Map> _devicesBox;
  late Box<Map> _logsBox;
  late Box<dynamic> _settingsBox;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  String _selfId = '';
  String get selfId => _selfId;

  /// Initialize Hive local engine and open all isolated local boxes
  Future<void> init() async {
    if (_isInitialized) return;

    await Hive.initFlutter();

    _devicesBox = await Hive.openBox<Map>(boxTrackedDevices);
    _logsBox = await Hive.openBox<Map>(boxLocationLogs);
    _settingsBox = await Hive.openBox<dynamic>(boxAppSettings);

    // Initialize or retrieve the cryptographic Self_ID
    final storedSelfId = _settingsBox.get(keySelfId) as String?;
    if (storedSelfId == null || storedSelfId.isEmpty) {
      _selfId = const Uuid().v4();
      await _settingsBox.put(keySelfId, _selfId);
    } else {
      _selfId = storedSelfId;
    }

    _isInitialized = true;
    notifyListeners();
  }

  // ===========================================================================
  // SELF ID MANAGEMENT
  // ===========================================================================

  /// Returns the current device's Self_ID
  String getSelfId() {
    return _selfId;
  }

  /// Sets a new Self_ID (e.g. for identity regeneration)
  Future<void> setSelfId(String newId) async {
    _selfId = newId;
    await _settingsBox.put(keySelfId, newId);
    notifyListeners();
  }

  /// Regenerates a new cryptographic Self_ID
  Future<String> regenerateSelfId() async {
    final newId = const Uuid().v4();
    await setSelfId(newId);
    return newId;
  }

  // ===========================================================================
  // BOX A: TRACKED DEVICES (CRUD)
  // ===========================================================================

  /// Retrieve all tracked devices sorted alphabetically or by creation
  List<TrackedDevice> getTrackedDevices() {
    if (!_isInitialized) return [];
    final devices = <TrackedDevice>[];
    for (final raw in _devicesBox.values) {
      try {
        devices.add(TrackedDevice.fromMap(raw));
      } catch (e) {
        debugPrint('[StorageService] Error parsing device: $e');
      }
    }
    devices.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return devices;
  }

  /// Get a single tracked device by UUID
  TrackedDevice? getTrackedDevice(String id) {
    if (!_isInitialized) return null;
    final raw = _devicesBox.get(id);
    if (raw == null) return null;
    return TrackedDevice.fromMap(raw);
  }

  /// Check if a given device UUID is registered in local tracking list
  bool isDeviceTracked(String id) {
    if (!_isInitialized) return false;
    final normalizedId = id.trim().toLowerCase();
    for (final key in _devicesBox.keys) {
      if (key.toString().toLowerCase() == normalizedId) {
        return true;
      }
    }
    return false;
  }

  /// Save or update a tracked device
  Future<void> saveTrackedDevice(TrackedDevice device) async {
    if (!_isInitialized) await init();
    await _devicesBox.put(device.id, device.toMap());
    notifyListeners();
  }

  /// Delete a tracked device and optionally its associated location logs
  Future<void> deleteTrackedDevice(String id, {bool deleteLogs = true}) async {
    if (!_isInitialized) return;
    await _devicesBox.delete(id);
    if (deleteLogs) {
      await deleteLogsForDevice(id);
    }
    notifyListeners();
  }

  // ===========================================================================
  // BOX B: LOCATION LOGS (CRUD)
  // ===========================================================================

  /// Retrieve location logs, optionally filtered by device ID and sorted descending by time
  List<LocationLog> getLocationLogs({String? deviceId}) {
    if (!_isInitialized) return [];
    final logs = <LocationLog>[];
    for (final raw in _logsBox.values) {
      try {
        final log = LocationLog.fromMap(raw);
        if (deviceId == null || log.deviceId.toLowerCase() == deviceId.toLowerCase()) {
          logs.add(log);
        }
      } catch (e) {
        debugPrint('[StorageService] Error parsing location log: $e');
      }
    }
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  /// Get the most recent location log for a given device
  LocationLog? getLatestLocationLog(String deviceId) {
    final logs = getLocationLogs(deviceId: deviceId);
    if (logs.isEmpty) return null;
    return logs.first;
  }

  /// Save a new location log entry
  Future<void> saveLocationLog(LocationLog log) async {
    if (!_isInitialized) await init();
    await _logsBox.put(log.id, log.toMap());
    notifyListeners();
  }

  /// Delete all logs associated with a specific device
  Future<void> deleteLogsForDevice(String deviceId) async {
    if (!_isInitialized) return;
    final keysToDelete = <dynamic>[];
    for (final key in _logsBox.keys) {
      final raw = _logsBox.get(key);
      if (raw != null && raw['device_id']?.toString().toLowerCase() == deviceId.toLowerCase()) {
        keysToDelete.add(key);
      }
    }
    await _logsBox.deleteAll(keysToDelete);
    notifyListeners();
  }

  /// Delete a specific log by its ID
  Future<void> deleteLog(String logId) async {
    if (!_isInitialized) return;
    await _logsBox.delete(logId);
    notifyListeners();
  }

  /// Clear all stored location logs
  Future<void> clearAllLogs() async {
    if (!_isInitialized) return;
    await _logsBox.clear();
    notifyListeners();
  }

  /// Clear all local storage databases (reset application)
  Future<void> resetAllData() async {
    if (!_isInitialized) return;
    await _devicesBox.clear();
    await _logsBox.clear();
    await _settingsBox.clear();
    await init();
    notifyListeners();
  }
}
