import 'dart:math' as math;
import 'package:uuid/uuid.dart';

/// SafeZone Model representing a designated geofenced safe area (e.g. Home, Office, Gym).
/// Tracked devices left inside a registered safe zone do not trigger separation alerts.
class SafeZone {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime createdAt;

  SafeZone({
    String? id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 100.0,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  factory SafeZone.fromMap(Map<dynamic, dynamic> map) {
    return SafeZone(
      id: map['id']?.toString() ?? const Uuid().v4(),
      name: map['name']?.toString() ?? 'Unnamed Safe Zone',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 100.0,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Calculates geodesic distance using the Haversine formula in meters.
  double distanceTo(double targetLat, double targetLng) {
    const double earthRadiusMeters = 6371000.0;
    final double dLat = _degreesToRadians(targetLat - latitude);
    final double dLng = _degreesToRadians(targetLng - longitude);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(latitude)) *
            math.cos(_degreesToRadians(targetLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Returns true if the provided coordinates fall within this safe zone's radius.
  bool contains(double targetLat, double targetLng) {
    if (latitude == 0.0 && longitude == 0.0) return false;
    return distanceTo(targetLat, targetLng) <= radiusMeters;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180.0);
  }

  SafeZone copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? radiusMeters,
    DateTime? createdAt,
  }) {
    return SafeZone(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafeZone && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'SafeZone(id: $id, name: $name, lat: $latitude, lng: $longitude, radius: ${radiusMeters}m)';
}
