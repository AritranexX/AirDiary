import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/tracked_device.dart';
import 'storage_service.dart';

/// Separation Alert Event triggered when a tracked device is left behind
class SeparationAlert {
  final TrackedDevice device;
  final DateTime lastSeen;
  final double? lastKnownLat;
  final double? lastKnownLng;
  final Duration elapsedSinceLastSeen;
  final String message;

  SeparationAlert({
    required this.device,
    required this.lastSeen,
    this.lastKnownLat,
    this.lastKnownLng,
    required this.elapsedSinceLastSeen,
    required this.message,
  });
}

/// Left-Behind Smart Separation Service.
/// Periodically evaluates whether registered devices have been absent for longer
/// than the configured threshold (e.g. 15 minutes) while the user is outside
/// designated Safe Zones (e.g. Home, Office). 100% offline and $0.
class SeparationService extends ChangeNotifier {
  static final SeparationService _instance = SeparationService._internal();
  factory SeparationService() => _instance;
  SeparationService._internal();

  final StorageService _storageService = StorageService();

  Timer? _evalTimer;
  final Set<String> _dismissedAlertDeviceIds = {};

  final StreamController<List<SeparationAlert>> _alertsController =
      StreamController<List<SeparationAlert>>.broadcast();
  Stream<List<SeparationAlert>> get alertsStream => _alertsController.stream;

  List<SeparationAlert> _activeAlerts = [];
  List<SeparationAlert> get activeAlerts => List.unmodifiable(_activeAlerts);

  bool get hasActiveAlerts => _activeAlerts.isNotEmpty;

  /// Start periodic evaluation timer
  void init() {
    _evalTimer?.cancel();
    _evalTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      checkSeparationStatus();
    });
    checkSeparationStatus();
  }

  /// Evaluates all tracked devices against safe zones and time thresholds
  Future<void> checkSeparationStatus() async {
    if (!_storageService.separationAlertsEnabled) {
      if (_activeAlerts.isNotEmpty) {
        _activeAlerts = [];
        _alertsController.add([]);
        notifyListeners();
      }
      return;
    }

    final safeZones = _storageService.getSafeZones();
    final devices = _storageService.getTrackedDevices();
    final thresholdMinutes = _storageService.separationThresholdMinutes;
    final now = DateTime.now();

    // 1. Check if user is currently inside a registered Safe Zone
    bool isInsideSafeZone = false;
    if (safeZones.isNotEmpty && (Platform.isAndroid || Platform.isIOS)) {
      try {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final currentPos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );

          for (final zone in safeZones) {
            if (zone.contains(currentPos.latitude, currentPos.longitude)) {
              isInsideSafeZone = true;
              debugPrint('[SeparationService] User inside safe zone: "${zone.name}". Separation alerts suppressed.');
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('[SeparationService] Geolocator safe zone evaluation error: $e');
      }
    }

    // If inside a safe zone, suppress left-behind alerts
    if (isInsideSafeZone) {
      if (_activeAlerts.isNotEmpty) {
        _activeAlerts = [];
        _alertsController.add([]);
        notifyListeners();
      }
      return;
    }

    // 2. Evaluate each device for absence beyond threshold
    final newAlerts = <SeparationAlert>[];

    for (final device in devices) {
      if (_dismissedAlertDeviceIds.contains(device.id)) {
        continue;
      }

      final latestLog = _storageService.getLatestLocationLog(device.id);
      final lastSeen = latestLog?.timestamp ?? device.createdAt;
      final elapsed = now.difference(lastSeen);

      if (elapsed.inMinutes >= thresholdMinutes) {
        newAlerts.add(
          SeparationAlert(
            device: device,
            lastSeen: lastSeen,
            lastKnownLat: latestLog?.latitude,
            lastKnownLng: latestLog?.longitude,
            elapsedSinceLastSeen: elapsed,
            message: 'Left behind: ${device.name} not detected for ${elapsed.inMinutes} mins outside safe zones.',
          ),
        );
      }
    }

    _activeAlerts = newAlerts;
    _alertsController.add(_activeAlerts);
    notifyListeners();
  }

  /// Dismiss an active separation alert for a device
  void dismissAlert(String deviceId) {
    _dismissedAlertDeviceIds.add(deviceId);
    _activeAlerts.removeWhere((a) => a.device.id == deviceId);
    _alertsController.add(_activeAlerts);
    notifyListeners();
  }

  /// Reset dismissed alerts (e.g. when a device is seen again)
  void resetDismissed(String deviceId) {
    _dismissedAlertDeviceIds.remove(deviceId);
  }

  /// Simulate a separation alert for UI testing / demonstration
  void simulateSeparationAlert(TrackedDevice device) {
    final alert = SeparationAlert(
      device: device,
      lastSeen: DateTime.now().subtract(const Duration(minutes: 25)),
      lastKnownLat: 37.7749,
      lastKnownLng: -122.4194,
      elapsedSinceLastSeen: const Duration(minutes: 25),
      message: 'SIMULATION: ${device.name} was left behind 25 minutes ago outside your safe zones.',
    );
    _activeAlerts.add(alert);
    _alertsController.add(_activeAlerts);
    notifyListeners();
  }

  @override
  void dispose() {
    _evalTimer?.cancel();
    _alertsController.close();
    super.dispose();
  }
}
