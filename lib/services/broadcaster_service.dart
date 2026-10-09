import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'package:uuid/uuid.dart';
import 'storage_service.dart';

/// Connectionless BLE Broadcaster (Beacon Engine).
/// Packs the local Self_ID into raw BLE manufacturer data bytes and broadcasts
/// as an ambient peer-to-peer beacon at optimized intervals to conserve battery.
class BroadcasterService extends ChangeNotifier {
  static final BroadcasterService _instance = BroadcasterService._internal();
  factory BroadcasterService() => _instance;
  BroadcasterService._internal();

  final StorageService _storageService = StorageService();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  static const int airDiaryManufacturerId = 0x01DA; // AirDiary Registered Identifier
  static const String airDiaryServiceUuid = '000001da-0000-1000-8000-00805f9b34fb';

  bool _isBroadcasting = false;
  bool get isBroadcasting => _isBroadcasting;

  bool _isSupported = false;
  bool get isSupported => _isSupported;

  String _statusMessage = 'Broadcaster initialized in idle state';
  String get statusMessage => _statusMessage;

  final List<String> _consoleLogs = [];
  List<String> get consoleLogs => List.unmodifiable(_consoleLogs);

  Timer? _periodicBroadcastTimer;

  /// Initialize Broadcaster engine and resolve Self_ID
  Future<void> init() async {
    _log('Initializing Connectionless BLE Broadcaster Engine...');

    try {
      // 1. Retrieve or generate Self_ID
      var selfId = _storageService.getSelfId();
      if (selfId.isEmpty) {
        selfId = await _storageService.regenerateSelfId();
        _log('Forged secure local client identifier: $selfId');
      } else {
        _log('Loaded existing Self_ID: $selfId');
      }

      // 2. Hardware capability check with desktop fail-safe
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        _log('Desktop environment detected (${Platform.operatingSystem}).');
        _statusMessage = 'Desktop environment: Peripheral advertising restricted by kernel. Passive tracking active.';
        _isSupported = false;
        notifyListeners();
        return;
      }

      final supported = await _peripheral.isSupported;
      _isSupported = supported;

      if (!supported) {
        _statusMessage = 'BLE Peripheral mode not supported on this hardware.';
        _log('Warning: BLE Peripheral advertising unsupported by current chipset.');
      } else {
        _statusMessage = 'Ready to broadcast AirDiary beacon.';
        _log('BLE Broadcaster ready. Ready to transmit Self_ID.');
      }
    } catch (e, stack) {
      _statusMessage = 'Broadcaster fallback: Kernel restriction intercepted safely.';
      _log('Safe Fail-Safe Intercept: $e');
      debugPrint('[BroadcasterService] Intercepted platform exception: $e\n$stack');
    }

    notifyListeners();
  }

  /// Start connectionless beacon broadcast routine
  Future<void> startBroadcasting() async {
    if (_isBroadcasting) return;

    try {
      final selfId = _storageService.getSelfId();
      if (selfId.isEmpty) {
        await init();
      }

      final activeId = _storageService.getSelfId();
      _log('Spinning up active BLE peripheral routine for Self_ID: $activeId');

      // Desktop kernel guard
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        _isBroadcasting = true;
        _statusMessage = 'Desktop Proximity Active (Simulated Beacon Mode)';
        _log('Desktop Proximity Active: Advertising signature in local memory subsystem.');
        notifyListeners();
        return;
      }

      // Convert 36-char UUID to 16 raw manufacturer bytes
      final uuidBytes = Uint8List.fromList(Uuid.parse(activeId));

      final advertiseData = AdvertiseDataCore(
        serviceUuid: activeId, // Also advertise full 128-bit UUID as service
        serviceUuids: [activeId, airDiaryServiceUuid],
        localName: 'AirDiary-${activeId.substring(0, 8)}',
        manufacturerId: airDiaryManufacturerId,
        manufacturerData: uuidBytes,
        includeTxPowerLevel: false,
      );

      final androidSettings = AndroidAdvertiseSettings(
        advertiseSettings: AdvertiseSettings(
          advertiseMode: AdvertiseMode.advertiseModeBalanced,
          txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
          timeout: 0,
          connectable: false,
        ),
      );

      await _peripheral.start(
        advertiseData: advertiseData,
        androidSettings: androidSettings,
      );

      _isBroadcasting = true;
      _statusMessage = 'Broadcasting AirDiary beacon signature';
      _log('Broadcasting active BLE packet with 16-byte raw signature.');
    } catch (e, stack) {
      _isBroadcasting = false;
      _statusMessage = 'Desktop/Platform restricted: $e';
      _log('Broadcasting exception caught safely: $e');
      debugPrint('[BroadcasterService] Start broadcasting error: $e\n$stack');
    }

    notifyListeners();
  }

  /// Stop active BLE broadcast routine
  Future<void> stopBroadcasting() async {
    _periodicBroadcastTimer?.cancel();
    _periodicBroadcastTimer = null;

    try {
      if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
        await _peripheral.stop();
      }
      _isBroadcasting = false;
      _statusMessage = 'Broadcaster stopped (Idle)';
      _log('BLE Broadcaster deactivated.');
    } catch (e) {
      _isBroadcasting = false;
      _statusMessage = 'Stopped with notice: $e';
      _log('Stop broadcast caught: $e');
    }

    notifyListeners();
  }

  /// Toggle broadcast state
  Future<void> toggleBroadcasting() async {
    if (_isBroadcasting) {
      await stopBroadcasting();
    } else {
      await startBroadcasting();
    }
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logEntry = '[$timestamp] $message';
    _consoleLogs.insert(0, logEntry);
    if (_consoleLogs.length > 50) {
      _consoleLogs.removeLast();
    }
    debugPrint('[Broadcaster] $message');
  }

  @override
  void dispose() {
    _periodicBroadcastTimer?.cancel();
    super.dispose();
  }
}
