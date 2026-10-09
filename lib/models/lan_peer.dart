/// Discovered Local LAN Peer device on same Wi-Fi subnet
class LanPeer {
  final String ip;
  final int port;
  final String selfId;
  final String deviceName;
  final DateTime lastSeen;

  const LanPeer({
    required this.ip,
    required this.port,
    required this.selfId,
    required this.deviceName,
    required this.lastSeen,
  });

  factory LanPeer.fromMap(Map<String, dynamic> map, String remoteIp) {
    return LanPeer(
      ip: remoteIp,
      port: (map['port'] as num?)?.toInt() ?? 41820,
      selfId: map['self_id']?.toString() ?? '',
      deviceName: map['device_name']?.toString() ?? 'AirDiary Node',
      lastSeen: DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ip': ip,
      'port': port,
      'self_id': selfId,
      'device_name': deviceName,
      'last_seen': lastSeen.toIso8601String(),
    };
  }

  LanPeer copyWith({
    String? ip,
    int? port,
    String? selfId,
    String? deviceName,
    DateTime? lastSeen,
  }) {
    return LanPeer(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      selfId: selfId ?? this.selfId,
      deviceName: deviceName ?? this.deviceName,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LanPeer &&
          runtimeType == other.runtimeType &&
          ip == other.ip &&
          selfId == other.selfId;

  @override
  int get hashCode => Object.hash(ip, selfId);

  @override
  String toString() => 'LanPeer($deviceName, $ip:$port, selfId: $selfId)';
}
