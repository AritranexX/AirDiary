import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lan_peer.dart';
import '../models/location_log.dart';
import '../models/tracked_device.dart';
import 'storage_service.dart';

/// Result summary of a peer-to-peer LAN synchronization session
class LanSyncResult {
  final String peerName;
  final String peerIp;
  final int syncedDevicesCount;
  final int syncedLogsCount;
  final bool isSuccess;
  final String? errorMessage;
  final DateTime timestamp;

  LanSyncResult({
    required this.peerName,
    required this.peerIp,
    required this.syncedDevicesCount,
    required this.syncedLogsCount,
    required this.isSuccess,
    this.errorMessage,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Zero-Cloud Local LAN Direct Socket P2P Sync Engine.
/// Provides serverless peer discovery via UDP broadcast and direct delta synchronization
/// via TCP sockets on port 41820 between devices on the same Wi-Fi subnet.
class LanSyncService extends ChangeNotifier {
  static final LanSyncService _instance = LanSyncService._internal();
  factory LanSyncService() => _instance;
  LanSyncService._internal();

  static const int defaultPort = 41820;
  static const String discoveryHeader = 'AIRDIARY_DISCOVERY_PING';

  final StorageService _storageService = StorageService();

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _discoveryTimer;

  bool _isServerRunning = false;
  bool get isServerRunning => _isServerRunning;

  bool _isDiscovering = false;
  bool get isDiscovering => _isDiscovering;

  final Map<String, LanPeer> _peersMap = {};
  List<LanPeer> get discoveredPeers => _peersMap.values.toList();

  final StreamController<List<LanPeer>> _peersController =
      StreamController<List<LanPeer>>.broadcast();
  Stream<List<LanPeer>> get peersStream => _peersController.stream;

  final StreamController<LanSyncResult> _syncResultController =
      StreamController<LanSyncResult>.broadcast();
  Stream<LanSyncResult> get syncResultStream => _syncResultController.stream;

  LanSyncResult? _lastSyncResult;
  LanSyncResult? get lastSyncResult => _lastSyncResult;

  String _statusMessage = 'LAN Sync ready (Standby)';
  String get statusMessage => _statusMessage;

  /// Start the background LAN discovery listener and TCP sync server
  Future<void> init() async {
    try {
      if (!_storageService.isInitialized) {
        await _storageService.init();
      }

      await _startTcpServer();
      await _startUdpListener();
      startPeriodicDiscovery();

      _statusMessage = 'LAN Sync engine active on port $defaultPort';
      debugPrint('[LanSyncService] Initialized successfully');
      notifyListeners();
    } catch (e) {
      _statusMessage = 'LAN Sync init notice: $e';
      debugPrint('[LanSyncService] Init Exception (Safely Intercepted): $e');
      notifyListeners();
    }
  }

  /// Start listening for incoming TCP sync requests from local peers
  Future<void> _startTcpServer() async {
    try {
      _tcpServer?.close();
      _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, defaultPort);
      _isServerRunning = true;
      _tcpServer!.listen(_handleIncomingTcpConnection, onError: (err) {
        debugPrint('[LanSyncService] TCP server error: $err');
      });
      debugPrint('[LanSyncService] TCP sync server listening on port $defaultPort');
    } catch (e) {
      debugPrint('[LanSyncService] Failed to bind TCP server on port $defaultPort: $e');
    }
  }

  /// Handle incoming TCP connection from a peer
  void _handleIncomingTcpConnection(Socket socket) {
    debugPrint('[LanSyncService] Incoming sync connection from ${socket.remoteAddress.address}');
    final buffer = <int>[];

    socket.listen(
      (data) {
        buffer.addAll(data);
      },
      onDone: () async {
        try {
          final rawJson = utf8.decode(buffer);
          final payload = jsonDecode(rawJson) as Map<String, dynamic>;

          if (payload['type'] == 'SYNC_REQUEST') {
            final remoteSenderName = payload['sender_name']?.toString() ?? 'Remote Peer';
            final remoteDevices = (payload['devices'] as List<dynamic>? ?? [])
                .map((d) => TrackedDevice.fromMap(d as Map<dynamic, dynamic>))
                .toList();
            final remoteLogs = (payload['logs'] as List<dynamic>? ?? [])
                .map((l) => LocationLog.fromMap(l as Map<dynamic, dynamic>))
                .toList();

            // Merge received items into local storage
            int mergedDevices = 0;
            for (final d in remoteDevices) {
              if (!_storageService.isDeviceTracked(d.id)) {
                await _storageService.saveTrackedDevice(d);
                mergedDevices++;
              }
            }

            int mergedLogs = 0;
            final localLogIds = _storageService.getLocationLogs().map((l) => l.id).toSet();
            for (final l in remoteLogs) {
              if (!localLogIds.contains(l.id)) {
                await _storageService.saveLocationLog(l);
                mergedLogs++;
              }
            }

            // Prepare reciprocal response with local devices and logs
            final localDevices = _storageService.getTrackedDevices().map((d) => d.toMap()).toList();
            final localLogs = _storageService.getLocationLogs().map((l) => l.toMap()).toList();

            final responsePayload = {
              'type': 'SYNC_RESPONSE',
              'sender_id': _storageService.selfId,
              'sender_name': _getHostDeviceName(),
              'devices': localDevices,
              'logs': localLogs,
              'merged_devices': mergedDevices,
              'merged_logs': mergedLogs,
            };

            final responseBytes = utf8.encode(jsonEncode(responsePayload));
            socket.add(responseBytes);
            await socket.flush();

            final result = LanSyncResult(
              peerName: remoteSenderName,
              peerIp: socket.remoteAddress.address,
              syncedDevicesCount: mergedDevices,
              syncedLogsCount: mergedLogs,
              isSuccess: true,
            );
            _lastSyncResult = result;
            _syncResultController.add(result);
            notifyListeners();
          }
        } catch (e) {
          debugPrint('[LanSyncService] Error processing incoming TCP payload: $e');
        } finally {
          socket.destroy();
        }
      },
      onError: (err) {
        debugPrint('[LanSyncService] Incoming TCP socket error: $err');
        socket.destroy();
      },
    );
  }

  /// Start UDP discovery listener
  Future<void> _startUdpListener() async {
    try {
      _udpSocket?.close();
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, defaultPort, reuseAddress: true, reusePort: true);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram != null) {
            _handleIncomingUdpDatagram(datagram);
          }
        }
      });
      debugPrint('[LanSyncService] UDP discovery listener active on port $defaultPort');
    } catch (e) {
      debugPrint('[LanSyncService] Failed to bind UDP listener: $e');
    }
  }

  /// Parse incoming UDP discovery packets
  void _handleIncomingUdpDatagram(Datagram datagram) {
    try {
      final msg = utf8.decode(datagram.data);
      if (msg.startsWith(discoveryHeader)) {
        final parts = msg.split(':');
        if (parts.length >= 4) {
          final peerSelfId = parts[1];
          final peerDeviceName = parts[2];
          final peerPort = int.tryParse(parts[3]) ?? defaultPort;

          // Ignore self-broadcasts
          if (peerSelfId == _storageService.selfId) return;

          final peer = LanPeer(
            ip: datagram.address.address,
            port: peerPort,
            selfId: peerSelfId,
            deviceName: peerDeviceName,
            lastSeen: DateTime.now(),
          );

          _peersMap[peerSelfId] = peer;
          _peersController.add(discoveredPeers);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[LanSyncService] UDP parsing error: $e');
    }
  }

  /// Broadcast discovery ping over local Wi-Fi subnet
  Future<void> broadcastDiscoveryPing() async {
    if (_udpSocket == null) return;
    try {
      final payload = '$discoveryHeader:${_storageService.selfId}:${_getHostDeviceName()}:$defaultPort';
      final data = utf8.encode(payload);

      // Broadcast to standard IPv4 subnet broadcast address
      _udpSocket!.send(data, InternetAddress('255.255.255.255'), defaultPort);
      _isDiscovering = true;
      notifyListeners();

      Future.delayed(const Duration(seconds: 2), () {
        _isDiscovering = false;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[LanSyncService] Broadcast discovery ping failed: $e');
    }
  }

  /// Start periodic background peer discovery
  void startPeriodicDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_storageService.lanSyncEnabled) {
        broadcastDiscoveryPing();
        _pruneStalePeers();
      }
    });
    broadcastDiscoveryPing();
  }

  /// Remove peers that haven't responded within 60 seconds
  void _pruneStalePeers() {
    final now = DateTime.now();
    final initialCount = _peersMap.length;
    _peersMap.removeWhere((_, peer) => now.difference(peer.lastSeen) > const Duration(seconds: 60));
    if (_peersMap.length != initialCount) {
      _peersController.add(discoveredPeers);
      notifyListeners();
    }
  }

  /// Perform active TCP two-way delta sync with a specific discovered peer
  Future<LanSyncResult> syncWithPeer(LanPeer peer) async {
    _statusMessage = 'Syncing with ${peer.deviceName} (${peer.ip})...';
    notifyListeners();

    Socket? clientSocket;
    try {
      clientSocket = await Socket.connect(peer.ip, peer.port, timeout: const Duration(seconds: 8));

      // 1. Prepare local payload
      final localDevices = _storageService.getTrackedDevices().map((d) => d.toMap()).toList();
      final localLogs = _storageService.getLocationLogs().map((l) => l.toMap()).toList();

      final requestPayload = {
        'type': 'SYNC_REQUEST',
        'sender_id': _storageService.selfId,
        'sender_name': _getHostDeviceName(),
        'devices': localDevices,
        'logs': localLogs,
      };

      clientSocket.add(utf8.encode(jsonEncode(requestPayload)));
      await clientSocket.flush();

      // 2. Read reciprocal response
      final responseBuffer = <int>[];
      final completer = Completer<LanSyncResult>();

      clientSocket.listen(
        (data) {
          responseBuffer.addAll(data);
        },
        onDone: () async {
          try {
            final raw = utf8.decode(responseBuffer);
            final json = jsonDecode(raw) as Map<String, dynamic>;

            if (json['type'] == 'SYNC_RESPONSE') {
              final remoteDevices = (json['devices'] as List<dynamic>? ?? [])
                  .map((d) => TrackedDevice.fromMap(d as Map<dynamic, dynamic>))
                  .toList();
              final remoteLogs = (json['logs'] as List<dynamic>? ?? [])
                  .map((l) => LocationLog.fromMap(l as Map<dynamic, dynamic>))
                  .toList();

              int mergedDevices = 0;
              for (final d in remoteDevices) {
                if (!_storageService.isDeviceTracked(d.id)) {
                  await _storageService.saveTrackedDevice(d);
                  mergedDevices++;
                }
              }

              int mergedLogs = 0;
              final localLogIds = _storageService.getLocationLogs().map((l) => l.id).toSet();
              for (final l in remoteLogs) {
                if (!localLogIds.contains(l.id)) {
                  await _storageService.saveLocationLog(l);
                  mergedLogs++;
                }
              }

              final result = LanSyncResult(
                peerName: peer.deviceName,
                peerIp: peer.ip,
                syncedDevicesCount: mergedDevices,
                syncedLogsCount: mergedLogs,
                isSuccess: true,
              );
              _lastSyncResult = result;
              _syncResultController.add(result);
              _statusMessage = 'Synced $mergedDevices devices & $mergedLogs logs with ${peer.deviceName}';
              notifyListeners();
              completer.complete(result);
            } else {
              completer.complete(
                LanSyncResult(
                  peerName: peer.deviceName,
                  peerIp: peer.ip,
                  syncedDevicesCount: 0,
                  syncedLogsCount: 0,
                  isSuccess: false,
                  errorMessage: 'Unexpected peer response type',
                ),
              );
            }
          } catch (e) {
            completer.complete(
              LanSyncResult(
                peerName: peer.deviceName,
                peerIp: peer.ip,
                syncedDevicesCount: 0,
                syncedLogsCount: 0,
                isSuccess: false,
                errorMessage: 'Payload decode error: $e',
              ),
            );
          }
        },
        onError: (err) {
          completer.complete(
            LanSyncResult(
              peerName: peer.deviceName,
              peerIp: peer.ip,
              syncedDevicesCount: 0,
              syncedLogsCount: 0,
              isSuccess: false,
              errorMessage: 'TCP socket connection error: $err',
            ),
          );
        },
      );

      return await completer.future;
    } catch (e) {
      final errorResult = LanSyncResult(
        peerName: peer.deviceName,
        peerIp: peer.ip,
        syncedDevicesCount: 0,
        syncedLogsCount: 0,
        isSuccess: false,
        errorMessage: e.toString(),
      );
      _lastSyncResult = errorResult;
      _syncResultController.add(errorResult);
      _statusMessage = 'Sync failed: $e';
      notifyListeners();
      return errorResult;
    } finally {
      clientSocket?.destroy();
    }
  }

  /// Helper to get a descriptive local device name based on platform
  String _getHostDeviceName() {
    if (Platform.isAndroid) return 'AirDiary Android Node';
    if (Platform.isIOS) return 'AirDiary iOS Node';
    if (Platform.isMacOS) return 'AirDiary Mac Node';
    if (Platform.isWindows) return 'AirDiary Windows Node';
    if (Platform.isLinux) return 'AirDiary Linux Node';
    return 'AirDiary Node';
  }

  /// Manually add a simulated peer for testing / UI demonstration
  void simulatePeer({String? name, String? ip}) {
    final simulated = LanPeer(
      ip: ip ?? '192.168.1.142',
      port: defaultPort,
      selfId: 'simulated-node-id-${DateTime.now().millisecondsSinceEpoch % 1000}',
      deviceName: name ?? 'AirDiary Desktop Node',
      lastSeen: DateTime.now(),
    );
    _peersMap[simulated.selfId] = simulated;
    _peersController.add(discoveredPeers);
    notifyListeners();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    _udpSocket?.close();
    _tcpServer?.close();
    _peersController.close();
    _syncResultController.close();
    super.dispose();
  }
}
