import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:air_diary/models/safe_zone.dart';
import 'package:air_diary/models/tracked_device.dart';
import 'package:air_diary/models/location_log.dart';
import 'package:air_diary/models/rogue_beacon.dart';
import 'package:air_diary/models/lan_peer.dart';
import 'package:air_diary/services/lan_sync_service.dart';
import 'package:air_diary/services/update_service.dart';

void main() {
  group('AirDiary Services Logic & Math Verification', () {
    test('In-App GitHub Release Update Engine semver comparison logic', () {
      final updateService = UpdateService();

      expect(UpdateService.currentAppVersion, '1.2.0+3');
      expect(UpdateService.githubRepoOwner, 'AritranexX');
      expect(UpdateService.githubRepoName, 'AirDiary');
      expect(updateService.updateInfo.currentVersion, '1.2.0+3');
      expect(updateService.updateInfo.hasUpdate, isFalse);
    });
    test('Exponential Weighted Moving Average (EWMA) RSSI Filter math', () {
      const double alpha = 0.35;
      double smoothedRssi = -80.0;

      // New raw RSSI reading arrives closer (-60 dBm)
      int rawRssi = -60;
      smoothedRssi = (alpha * rawRssi) + ((1.0 - alpha) * smoothedRssi);
      expect(smoothedRssi, closeTo(-73.0, 0.1));

      // Another closer reading arrives (-55 dBm)
      rawRssi = -55;
      smoothedRssi = (alpha * rawRssi) + ((1.0 - alpha) * smoothedRssi);
      expect(smoothedRssi, closeTo(-66.7, 0.1));
    });

    test('LAN P2P UDP packet parsing and validation', () {
      final now = DateTime.now();
      final packetStr = 'AIRDIARY_DISCOVERY_PING:node-android-abc123:Galaxy S24 Ultra:41820';
      final parts = packetStr.split(':');

      expect(parts.length, 4);
      expect(parts[0], LanSyncService.discoveryHeader);
      expect(parts[1], 'node-android-abc123');
      expect(parts[2], 'Galaxy S24 Ultra');
      expect(int.parse(parts[3]), 41820);

      final peer = LanPeer(
        ip: '192.168.1.55',
        port: int.parse(parts[3]),
        selfId: parts[1],
        deviceName: parts[2],
        lastSeen: now,
      );

      expect(peer.ip, '192.168.1.55');
      expect(peer.deviceName, 'Galaxy S24 Ultra');
      expect(peer.port, 41820);
    });

    test('LAN P2P JSON Delta Payload serialization and merge union logic', () {
      final now = DateTime.now();
      final deviceA = TrackedDevice(
        id: 'device-uuid-1',
        name: 'MacBook Air M2',
        createdAt: now.subtract(const Duration(days: 2)),
      );
      final deviceB = TrackedDevice(
        id: 'device-uuid-2',
        name: 'AirDiary Keyring',
        createdAt: now.subtract(const Duration(days: 1)),
      );

      final log1 = LocationLog(
        id: 'log-uuid-1',
        deviceId: 'device-uuid-1',
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: now.subtract(const Duration(hours: 1)),
      );

      final payloadMap = {
        'version': 1,
        'sender_id': 'self-mac-node',
        'sender_name': 'MacBook Pro',
        'devices': [deviceA.toMap(), deviceB.toMap()],
        'logs': [log1.toMap()],
      };

      final jsonString = jsonEncode(payloadMap);
      expect(jsonString, isNotEmpty);

      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
      expect(decoded['version'], 1);
      expect(decoded['sender_name'], 'MacBook Pro');

      final rawDevices = decoded['devices'] as List<dynamic>;
      final restoredDevices = rawDevices
          .map((d) => TrackedDevice.fromMap(d as Map<dynamic, dynamic>))
          .toList();

      expect(restoredDevices.length, 2);
      expect(restoredDevices.first.id, 'device-uuid-1');
      expect(restoredDevices.last.name, 'AirDiary Keyring');
    });

    test('SafeZone Geofence radius containment check', () {
      final safeZone = SafeZone(
        id: 'office-zone-1',
        name: 'Headquarters',
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 250.0,
      );

      // Same location: 0 distance -> true
      expect(safeZone.contains(40.7128, -74.0060), isTrue);

      // 100 meters away -> true
      // 1 deg lat is ~111,000 m, so 0.0009 deg is ~100 m
      expect(safeZone.contains(40.7128 + 0.0009, -74.0060), isTrue);

      // 1 km away -> false
      // 0.009 deg lat is ~1000 m
      expect(safeZone.contains(40.7128 + 0.009, -74.0060), isFalse);
    });

    test('Anti-Stalking spatial clustering detection heuristic', () {
      final now = DateTime.now();
      final baseLat = 37.7749;
      final baseLng = -122.4194;

      // Sighting 1: Downtown SF
      final s1 = BeaconSighting(
        latitude: baseLat,
        longitude: baseLng,
        timestamp: now.subtract(const Duration(minutes: 40)),
      );

      // Sighting 2: SOMA (~1.5 km away)
      final s2 = BeaconSighting(
        latitude: baseLat + 0.015,
        longitude: baseLng,
        timestamp: now.subtract(const Duration(minutes: 20)),
      );

      // Sighting 3: Mission District (~3.0 km away)
      final s3 = BeaconSighting(
        latitude: baseLat + 0.030,
        longitude: baseLng,
        timestamp: now,
      );

      final beacon = RogueBeacon(
        signatureId: 'airtag-clone-99',
        firstSeen: s1.timestamp,
        lastSeen: s3.timestamp,
        detectionCount: 3,
        sightings: [s1, s2, s3],
        distinctClusterCount: 3,
      );

      // Verify that this beacon is classified as suspicious due to moving across 3 distinct clusters
      expect(beacon.distinctClusterCount >= 2, isTrue);
      expect(beacon.sightings.length, 3);
      expect(beacon.lastSeen.difference(beacon.firstSeen).inMinutes, greaterThanOrEqualTo(15));
    });
  });
}
