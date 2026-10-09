import 'package:flutter_test/flutter_test.dart';
import 'package:air_diary/models/tracked_device.dart';
import 'package:air_diary/models/location_log.dart';

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
  });
}
