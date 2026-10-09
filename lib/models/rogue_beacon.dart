/// Sighting record representing a geographic coordinate cluster where an unknown beacon was detected
class BeaconSighting {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const BeaconSighting({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory BeaconSighting.fromMap(Map<dynamic, dynamic> map) {
    return BeaconSighting(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// RogueBeacon Model capturing suspicious un-paired BLE beacon signatures
/// detected travelling across multiple distinct coordinate clusters over time.
class RogueBeacon {
  final String signatureId;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int detectionCount;
  final List<BeaconSighting> sightings;
  final int distinctClusterCount;
  final bool isDismissed;

  const RogueBeacon({
    required this.signatureId,
    required this.firstSeen,
    required this.lastSeen,
    this.detectionCount = 1,
    this.sightings = const [],
    this.distinctClusterCount = 1,
    this.isDismissed = false,
  });

  factory RogueBeacon.fromMap(Map<dynamic, dynamic> map) {
    final rawSightings = map['sightings'] as List<dynamic>? ?? [];
    final parsedSightings = rawSightings
        .map((s) => BeaconSighting.fromMap(s as Map<dynamic, dynamic>))
        .toList();

    return RogueBeacon(
      signatureId: map['signature_id']?.toString() ?? '',
      firstSeen: map['first_seen'] != null
          ? DateTime.tryParse(map['first_seen'].toString()) ?? DateTime.now()
          : DateTime.now(),
      lastSeen: map['last_seen'] != null
          ? DateTime.tryParse(map['last_seen'].toString()) ?? DateTime.now()
          : DateTime.now(),
      detectionCount: (map['detection_count'] as num?)?.toInt() ?? 1,
      sightings: parsedSightings,
      distinctClusterCount: (map['distinct_cluster_count'] as num?)?.toInt() ?? 1,
      isDismissed: map['is_dismissed'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'signature_id': signatureId,
      'first_seen': firstSeen.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
      'detection_count': detectionCount,
      'sightings': sightings.map((s) => s.toMap()).toList(),
      'distinct_cluster_count': distinctClusterCount,
      'is_dismissed': isDismissed,
    };
  }

  RogueBeacon copyWith({
    String? signatureId,
    DateTime? firstSeen,
    DateTime? lastSeen,
    int? detectionCount,
    List<BeaconSighting>? sightings,
    int? distinctClusterCount,
    bool? isDismissed,
  }) {
    return RogueBeacon(
      signatureId: signatureId ?? this.signatureId,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      detectionCount: detectionCount ?? this.detectionCount,
      sightings: sightings ?? this.sightings,
      distinctClusterCount: distinctClusterCount ?? this.distinctClusterCount,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RogueBeacon &&
          runtimeType == other.runtimeType &&
          signatureId == other.signatureId;

  @override
  int get hashCode => signatureId.hashCode;

  @override
  String toString() =>
      'RogueBeacon(id: $signatureId, sightings: ${sightings.length}, clusters: $distinctClusterCount, dismissed: $isDismissed)';
}
