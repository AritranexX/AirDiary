/// AirDiary Tracked Device Schema
/// Strictly captures device UUID, human-readable name/descriptor, and creation timestamp.
class TrackedDevice {
  final String id;
  final String name;
  final DateTime createdAt;

  const TrackedDevice({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  /// Factory constructor to deserialize from local storage Map
  factory TrackedDevice.fromMap(Map<dynamic, dynamic> map) {
    return TrackedDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Unnamed Device',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Serialize to Map for local Hive persistence
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  TrackedDevice copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return TrackedDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackedDevice &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TrackedDevice(id: $id, name: $name, createdAt: ${createdAt.toIso8601String()})';
}
