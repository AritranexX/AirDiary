import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:air_diary/models/tracked_device.dart';
import 'package:air_diary/models/location_log.dart';
import 'package:air_diary/models/safe_zone.dart';
import 'package:air_diary/models/rogue_beacon.dart';
import 'package:air_diary/models/lan_peer.dart';
import 'package:air_diary/services/lan_sync_service.dart';

void main() {
  group('AirDiary Models & Protocol Tests', () {
    test('TrackedDevice serialization and deserialization', () {
      final now = DateTime.now();
      final device = TrackedDevice(
        id: '12345678-1234-1234-1234-123456789abc',
        name: 'MacBook Pro M3',
        createdAt: now,
      );

      final map = device.toMap();
      expect(map['id'], '12345678-1234-1234-1234-123456789abc');
      expect(map['name'], 'MacBook Pro M3');
      expect(map['created_at'], now.toIso8601String());

      final restored = TrackedDevice.fromMap(map);
      expect(restored.id, device.id);
      expect(restored.name, device.name);
      expect(restored.createdAt.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('LocationLog desktop proximity and coordinates flag', () {
      final now = DateTime.now();
      final desktopLog = LocationLog(
        deviceId: '12345678-1234-1234-1234-123456789abc',
        latitude: 0.0,
        longitude: 0.0,
        timestamp: now,
        tag: 'Desktop Proximity Only',
      );

      expect(desktopLog.isDesktopProximity, isTrue);

      final gpsLog = LocationLog(
        deviceId: '12345678-1234-1234-1234-123456789abc',
        latitude: 37.7749,
        longitude: -122.4194,
        timestamp: now,
        tag: 'Mobile GPS Location',
      );

      expect(gpsLog.isDesktopProximity, isFalse);

      final map = gpsLog.toMap();
      final restored = LocationLog.fromMap(map);
      expect(restored.latitude, 37.7749);
      expect(restored.longitude, -122.4194);
      expect(restored.isDesktopProximity, isFalse);
    });

    test('SafeZone Haversine containment and distance math', () {
      final zone = SafeZone(
        id: 'home-zone-01',
        name: 'Home Sanctuary',
        latitude: 37.7749,
        longitude: -122.4194,
        radiusMeters: 100.0,
      );

      // Same coordinate is 0 distance and inside zone
      expect(zone.distanceTo(37.7749, -122.4194), closeTo(0.0, 0.1));
      expect(zone.contains(37.7749, -122.4194), isTrue);

      // Coordinate roughly 50m away is inside zone
      // 0.00045 deg lat is approx 50m
      expect(zone.contains(37.7749 + 0.00045, -122.4194), isTrue);

      // Coordinate 2km away is outside zone
      // 0.02 deg lat is approx 2.2km
      expect(zone.contains(37.7749 + 0.02, -122.4194), isFalse);
      expect(zone.distanceTo(37.7749 + 0.02, -122.4194), greaterThan(1000.0));

      // Serialization & Deserialization
      final map = zone.toMap();
      expect(map['name'], 'Home Sanctuary');
      expect(map['radius_meters'], 100.0);

      final restored = SafeZone.fromMap(map);
      expect(restored.id, 'home-zone-01');
      expect(restored.name, 'Home Sanctuary');
      expect(restored.radiusMeters, 100.0);
    });

    test('RogueBeacon multi-cluster risk level calculation', () {
      final now = DateTime.now();
      final beaconLow = RogueBeacon(
        signatureId: 'beacon-low-01',
        firstSeen: now.subtract(const Duration(minutes: 5)),
        lastSeen: now,
        distinctClusterCount: 1,
      );
      expect(beaconLow.distinctClusterCount, 1);
      expect(beaconLow.distinctClusterCount >= 2, isFalse);

      final beaconMedium = RogueBeacon(
        signatureId: 'beacon-med-02',
        firstSeen: now.subtract(const Duration(minutes: 20)),
        lastSeen: now,
        distinctClusterCount: 2,
      );
      expect(beaconMedium.distinctClusterCount, 2);
      expect(beaconMedium.distinctClusterCount >= 2, isTrue);

      final beaconHigh = RogueBeacon(
        signatureId: 'beacon-high-03',
        firstSeen: now.subtract(const Duration(hours: 1)),
        lastSeen: now,
        distinctClusterCount: 3,
        sightings: [
          BeaconSighting(latitude: 37.7749, longitude: -122.4194, timestamp: now.subtract(const Duration(hours: 1))),
          BeaconSighting(latitude: 37.7849, longitude: -122.4094, timestamp: now.subtract(const Duration(minutes: 30))),
          BeaconSighting(latitude: 37.7949, longitude: -122.3994, timestamp: now),
        ],
      );
      expect(beaconHigh.distinctClusterCount, 3);
      expect(beaconHigh.sightings.length, 3);

      final map = beaconHigh.toMap();
      final restored = RogueBeacon.fromMap(map);
      expect(restored.signatureId, 'beacon-high-03');
      expect(restored.distinctClusterCount, 3);
      expect(restored.sightings.length, 3);
    });

    test('LanPeer model and synchronization results', () {
      final peer = LanPeer(
        ip: '192.168.1.150',
        port: 41820,
        selfId: 'airdiary-node-mac',
        deviceName: 'MacBook Pro Node',
        lastSeen: DateTime.now(),
      );

      expect(peer.ip, '192.168.1.150');
      expect(peer.port, 41820);
      expect(peer.deviceName, 'MacBook Pro Node');

      final result = LanSyncResult(
        isSuccess: true,
        peerIp: peer.ip,
        peerName: peer.deviceName,
        syncedDevicesCount: 3,
        syncedLogsCount: 42,
        timestamp: DateTime.now(),
      );

      expect(result.isSuccess, isTrue);
      expect(result.syncedDevicesCount, 3);
      expect(result.syncedLogsCount, 42);
    });

    test('Log-Distance Path Loss RSSI Distance Estimation Math', () {
      // Path loss formula: Distance = 10 ^ ((TxPower - RSSI) / (10 * n))
      // Standard BLE TxPower at 1m = -59.0 dBm, Path Loss Exponent n = 2.2
      const double txPower = -59.0;
      const double n = 2.2;

      double estimateDistance(int rssi) {
        if (rssi >= 0) return 0.1;
        final ratio = (txPower - rssi) / (10.0 * n);
        return math.pow(10.0, ratio).toDouble();
      }

      // At exactly TxPower (-59 dBm), distance should be ~1.0 meter
      expect(estimateDistance(-59), closeTo(1.0, 0.05));

      // At -40 dBm (very close), distance should be < 0.2 meters
      expect(estimateDistance(-40), lessThan(0.5));

      // At -80 dBm (moderate distance), distance should be approx 8-10 meters
      expect(estimateDistance(-80), greaterThan(5.0));

      // At -95 dBm (far signal limit), distance should be > 20 meters
      expect(estimateDistance(-95), greaterThan(20.0));
    });
  });
}
