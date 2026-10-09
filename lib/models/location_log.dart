import 'package:uuid/uuid.dart';

/// AirDiary Location Log Schema
/// Strictly captures device ID, GPS latitude, GPS longitude, timestamp, and optional proximity tag.
class LocationLog {
  final String id;
  final String deviceId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final String? tag;

  LocationLog({
    String? id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.tag,
  }) : id = id ?? const Uuid().v4();

  /// Factory constructor to deserialize from local storage Map
  factory LocationLog.fromMap(Map<dynamic, dynamic> map) {
    return LocationLog(
      id: map['id']?.toString() ?? const Uuid().v4(),
      deviceId: map['device_id']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      tag: map['tag']?.toString(),
    );
  }

  /// Serialize to Map for local Hive persistence
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      if (tag != null) 'tag': tag,
    };
  }

  bool get isDesktopProximity =>
      (latitude == 0.0 && longitude == 0.0) || tag == 'Desktop Proximity Only';

  LocationLog copyWith({
    String? id,
    String? deviceId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    String? tag,
  }) {
    return LocationLog(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      tag: tag ?? this.tag,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocationLog &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'LocationLog(id: $id, deviceId: $deviceId, lat: $latitude, lng: $longitude, timestamp: ${timestamp.toIso8601String()}, tag: $tag)';
}
