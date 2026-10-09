import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/rogue_beacon.dart';
import 'storage_service.dart';

/// Anti-Stalking & Rogue Beacon Detection Engine.
/// Detects un-paired BLE beacons travelling alongside the user across multiple
/// distinct geographic coordinate clusters over time. Runs 100% locally with zero cloud telemetry.
class AntiStalkingService extends ChangeNotifier {
  static final AntiStalkingService _instance = AntiStalkingService._internal();
  factory AntiStalkingService() => _instance;
  AntiStalkingService._internal();

  final StorageService _storageService = StorageService();

  // In-memory cooldown per signature so we don't spam GPS queries on every packet
  final Map<String, DateTime> _sightingCooldownMap = {};

  final StreamController<RogueBeacon> _alertController =
      StreamController<RogueBeacon>.broadcast();
  Stream<RogueBeacon> get alertStream => _alertController.stream;

  RogueBeacon? _lastAlertBeacon;
  RogueBeacon? get lastAlertBeacon => _lastAlertBeacon;

  // Minimum distance between sightings to count as a distinct cluster (150m)
  static const double clusterThresholdMeters = 150.0;

  // Minimum time span (e.g. 15 minutes) and cluster count (>= 3) for high-risk alert
  static const Duration minimumStalkingDuration = Duration(minutes: 15);
  static const int minimumClusterAlertCount = 3;

  /// Process an ambient (un-paired) beacon detection
  Future<void> processAmbientSighting(String signatureId, int rssi) async {
    if (!_storageService.antiStalkingEnabled) return;

    final normalizedSig = signatureId.trim().toLowerCase();

    // Ignore own broadcast Self_ID
    if (normalizedSig == _storageService.selfId.trim().toLowerCase()) {
      return;
    }

    // Ignore known paired / tracked devices
    if (_storageService.isDeviceTracked(normalizedSig)) {
      return;
    }

    final now = DateTime.now();

    // 1-minute throttle per unknown signature for GPS location capture
    final lastRecorded = _sightingCooldownMap[normalizedSig];
    if (lastRecorded != null && now.difference(lastRecorded) < const Duration(minutes: 1)) {
      return;
    }
    _sightingCooldownMap[normalizedSig] = now;

    // Acquire GPS position if mobile
    double lat = 0.0;
    double lng = 0.0;

    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final hasPermission = await Geolocator.checkPermission();
        if (hasPermission == LocationPermission.always ||
            hasPermission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );
          lat = pos.latitude;
          lng = pos.longitude;
        }
      } catch (e) {
        debugPrint('[AntiStalkingService] GPS acquisition error: $e');
      }
    }

    final sighting = BeaconSighting(
      latitude: lat,
      longitude: lng,
      timestamp: now,
    );

    // Retrieve or initialize RogueBeacon record
    final existing = _storageService.getRogueBeacon(normalizedSig);
    final updatedSightings = existing != null
        ? [...existing.sightings, sighting]
        : [sighting];

    // Compute distinct spatial clusters
    final distinctClusters = _computeDistinctClusters(updatedSightings);
    final firstSeen = existing?.firstSeen ?? now;
    final detectionCount = (existing?.detectionCount ?? 0) + 1;

    final updatedBeacon = RogueBeacon(
      signatureId: normalizedSig,
      firstSeen: firstSeen,
      lastSeen: now,
      detectionCount: detectionCount,
      sightings: updatedSightings,
      distinctClusterCount: distinctClusters,
      isDismissed: existing?.isDismissed ?? false,
    );

    await _storageService.saveRogueBeacon(updatedBeacon);

    // Trigger alert if rogue conditions are met:
    // 1. Moving across >= 3 distinct clusters, OR
    // 2. Seen across >= 2 distinct clusters spanning >= 15 minutes
    final span = now.difference(firstSeen);
    final isSuspicious = (distinctClusters >= minimumClusterAlertCount) ||
        (distinctClusters >= 2 && span >= minimumStalkingDuration);

    if (isSuspicious && !updatedBeacon.isDismissed) {
      _lastAlertBeacon = updatedBeacon;
      _alertController.add(updatedBeacon);
      debugPrint('[AntiStalkingService] SUSPICIOUS BEACON DETECTED: $normalizedSig across $distinctClusters clusters!');
      notifyListeners();
    }
  }

  /// Calculates the number of spatially distinct coordinate clusters
  int _computeDistinctClusters(List<BeaconSighting> sightings) {
    final validSightings = sightings.where((s) => s.latitude != 0.0 || s.longitude != 0.0).toList();
    if (validSightings.isEmpty) {
      return 1;
    }

    final clusterCenters = <BeaconSighting>[validSightings.first];

    for (int i = 1; i < validSightings.length; i++) {
      final s = validSightings[i];
      bool inExistingCluster = false;

      for (final center in clusterCenters) {
        final dist = _calculateDistanceMeters(
          s.latitude,
          s.longitude,
          center.latitude,
          center.longitude,
        );
        if (dist < clusterThresholdMeters) {
          inExistingCluster = true;
          break;
        }
      }

      if (!inExistingCluster) {
        clusterCenters.add(s);
      }
    }

    return clusterCenters.length;
  }

  /// Haversine distance between two coordinates in meters
  static double _calculateDistanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = (lat2 - lat1) * (math.pi / 180.0);
    final double dLng = (lng2 - lng1) * (math.pi / 180.0);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Manually simulate a rogue beacon alert (for debugging & security verification)
  Future<void> simulateRogueBeacon({
    String? signatureId,
    int clusterCount = 3,
  }) async {
    final sig = signatureId ?? 'simulated-rogue-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final now = DateTime.now();

    final sightings = <BeaconSighting>[
      BeaconSighting(latitude: 37.7749, longitude: -122.4194, timestamp: now.subtract(const Duration(minutes: 30))),
      BeaconSighting(latitude: 37.7849, longitude: -122.4094, timestamp: now.subtract(const Duration(minutes: 15))),
      BeaconSighting(latitude: 37.7949, longitude: -122.3994, timestamp: now),
    ];

    final simulated = RogueBeacon(
      signatureId: sig,
      firstSeen: now.subtract(const Duration(minutes: 30)),
      lastSeen: now,
      detectionCount: 12,
      sightings: sightings,
      distinctClusterCount: clusterCount,
      isDismissed: false,
    );

    await _storageService.saveRogueBeacon(simulated);
    _lastAlertBeacon = simulated;
    _alertController.add(simulated);
    notifyListeners();
  }

  @override
  void dispose() {
    _alertController.close();
    super.dispose();
  }
}
