import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/tracked_device.dart';
import '../services/broadcaster_service.dart';
import '../services/storage_service.dart';

/// Offline Device Pairing Screen
/// Provides zero-server visual synchronization via QR Code generation and camera scanning,
/// alongside a manual alphanumeric fallback for desktop systems without camera sensors.
class PairView extends StatefulWidget {
  const PairView({super.key});

  @override
  State<PairView> createState() => _PairViewState();
}

class _PairViewState extends State<PairView> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final BroadcasterService _broadcasterService = BroadcasterService();

  late TabController _tabController;

  // Manual entry controllers
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  MobileScannerController? _scannerController;
  bool _isScannerStarted = false;
  bool _hasCameraError = false;
  String _cameraErrorMessage = '';
  bool _forceManualMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _storageService.addListener(_onStorageUpdate);
    _broadcasterService.addListener(_onStorageUpdate);

    // Initialize scanner for supported platforms
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      _initCamera();
    } else {
      _forceManualMode = true;
    }
  }

  void _onStorageUpdate() {
    if (mounted) setState(() {});
  }

  void _initCamera() {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      _isScannerStarted = true;
    } catch (e) {
      _hasCameraError = true;
      _cameraErrorMessage = 'Camera initialization failed: $e';
      debugPrint(_cameraErrorMessage);
      _forceManualMode = true;
    }
  }

  @override
  void dispose() {
    _storageService.removeListener(_onStorageUpdate);
    _broadcasterService.removeListener(_onStorageUpdate);
    _tabController.dispose();
    _idController.dispose();
    _nameController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  /// Handle QR barcode capture from camera stream
  void _onBarcodeDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    // Check if detected string is UUID or alphanumeric ID
    if (_idController.text != rawValue) {
      setState(() {
        _idController.text = rawValue;
        if (_nameController.text.isEmpty) {
          _nameController.text = 'Device-${rawValue.length > 8 ? rawValue.substring(0, 8) : rawValue}';
        }
      });

      _showPairConfirmationDialog(rawValue);
    }
  }

  /// Show popup dialog after scanning to confirm device registration
  void _showPairConfirmationDialog(String scannedId) {
    final dialogNameController = TextEditingController(
      text: _nameController.text.isNotEmpty
          ? _nameController.text
          : 'Device-${scannedId.length > 8 ? scannedId.substring(0, 8) : scannedId}',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Device Scanned', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A unique AirDiary beacon ID was intercepted via camera:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF13161F),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(
                scannedId,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dialogNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Device Descriptor / Name',
                labelStyle: TextStyle(color: Colors.white70),
                hintText: 'e.g. My Laptop, Keys, Backpack',
                hintStyle: TextStyle(color: Colors.white24),
                prefixIcon: Icon(Icons.label_outline, color: Color(0xFF00E676)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final finalName = dialogNameController.text.trim().isNotEmpty
                  ? dialogNameController.text.trim()
                  : 'Tracked Device';
              await _saveDevice(scannedId, finalName);
              if (!mounted) return;
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF00E676),
                  content: Text('Successfully registered "$finalName"', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              );
            },
            child: const Text('Save Device', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Save tracked device to Hive Box A
  Future<void> _saveDevice(String id, String name) async {
    final newDevice = TrackedDevice(
      id: id.trim().toLowerCase(),
      name: name.trim().isNotEmpty ? name.trim() : 'Unnamed Target',
      createdAt: DateTime.now(),
    );

    await _storageService.saveTrackedDevice(newDevice);
    _idController.clear();
    _nameController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final selfId = _storageService.getSelfId();
    final isBroadcasting = _broadcasterService.isBroadcasting;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F17),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner, color: Color(0xFF00E676), size: 22),
            SizedBox(width: 10),
            Text('Device Synchronization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        backgroundColor: const Color(0xFF131622),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E676),
          indicatorWeight: 3,
          labelColor: const Color(0xFF00E676),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code, size: 20), text: 'My Broadcast QR'),
            Tab(icon: Icon(Icons.add_link, size: 20), text: 'Pair / Add Device'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMyBeaconTab(selfId, isBroadcasting),
          _buildPairDeviceTab(),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: MY BEACON ID & QR CODE GENERATION
  // ===========================================================================
  Widget _buildMyBeaconTab(String selfId, bool isBroadcasting) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Broadcast Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isBroadcasting
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : Colors.orangeAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isBroadcasting ? const Color(0xFF00E676) : Colors.orangeAccent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBroadcasting ? Icons.sensors : Icons.sensors_off,
                      color: isBroadcasting ? const Color(0xFF00E676) : Colors.orangeAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isBroadcasting ? 'Broadcasting Active (Peer Beacon)' : 'Broadcaster Idle (Standby)',
                      style: TextStyle(
                        color: isBroadcasting ? const Color(0xFF00E676) : Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // QR Code Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161A28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'Scan this QR from another AirDiary device to pair offline:',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    // QR Image rendered via qr_flutter
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: selfId.isNotEmpty ? selfId : 'AirDiary-Initializing',
                        version: QrVersions.auto,
                        size: 220.0,
                        backgroundColor: Colors.white,
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        padding: const EdgeInsets.all(4),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Self_ID display box
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D0F17),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Host Cryptographic Self_ID',
                            style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            selfId,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF00E5FF),
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: selfId));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Self_ID copied to clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy ID'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _showRegenerateIdDialog,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Regenerate ID'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Info note
              const Card(
                color: Color(0xFF131722),
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: Color(0xFF00E676), size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Zero-Server Privacy: Your Self_ID never touches any central cloud or database. Pairing happens strictly through optical synchronization.',
                          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: PAIR / ADD DEVICE (CAMERA + MANUAL FALLBACK)
  // ===========================================================================
  Widget _buildPairDeviceTab() {
    final trackedDevices = _storageService.getTrackedDevices();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scanner / Input Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161A28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _forceManualMode ? 'Manual Device Entry' : 'Scan Target QR Code',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        // Mode toggle
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _forceManualMode = !_forceManualMode;
                            });
                          },
                          icon: Icon(
                            _forceManualMode ? Icons.camera_alt : Icons.keyboard,
                            size: 16,
                            color: const Color(0xFF00E676),
                          ),
                          label: Text(
                            _forceManualMode ? 'Use Camera' : 'Manual Entry',
                            style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Camera or Manual Input Form
                    if (!_forceManualMode && _isScannerStarted && !_hasCameraError)
                      _buildCameraScannerWidget()
                    else
                      _buildManualInputForm(),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Registered Devices Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tracked Devices',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (trackedDevices.isNotEmpty)
                    Text(
                      'Synchronized locally in Hive',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // List of Tracked Devices
              if (trackedDevices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161A28).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.devices_other, color: Colors.white24, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'No peer devices registered yet',
                        style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Scan a friend’s QR code or add their UUID manually above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: trackedDevices.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final device = trackedDevices[index];
                    return _buildTrackedDeviceTile(device);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live Mobile Scanner preview with styled overlay
  Widget _buildCameraScannerWidget() {
    return Column(
      children: [
        Container(
          height: 240,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E676), width: 1.5),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: _onBarcodeDetected,
                errorBuilder: (context, error) {
                  return Container(
                    color: const Color(0xFF131622),
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off, color: Colors.orangeAccent, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'Camera Error: ${error.errorCode.name}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00E676),
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () {
                              setState(() {
                                _forceManualMode = true;
                              });
                            },
                            child: const Text('Switch to Manual Entry'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              // Corner Overlay Target Box
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF00E676), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Point camera at an AirDiary QR code to pair automatically',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  /// Manual alphanumeric fallback input form for desktop/camera-less machines
  Widget _buildManualInputForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasCameraError || Platform.isWindows || Platform.isLinux)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF00E5FF), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Platform.isWindows || Platform.isLinux
                          ? 'Desktop hardware mode: Camera capture substituted with direct manual UUID pairing.'
                          : 'Camera inactive: Manual alphanumeric input mode enabled.',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          // Target UUID field
          TextFormField(
            controller: _idController,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Target Device UUID / Alphanumeric ID',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: 'e.g. 550e8400-e29b-41d4-a716-446655440000',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              prefixIcon: const Icon(Icons.fingerprint, color: Color(0xFF00E5FF)),
              filled: true,
              fillColor: const Color(0xFF0D0F17),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00E676))),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Device ID cannot be empty';
              }
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Device Name field
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Device Name / Descriptor',
              labelStyle: const TextStyle(color: Colors.white70),
              hintText: 'e.g. Pixel 8, Work MacBook, Keys Tag',
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
              prefixIcon: const Icon(Icons.label_outline, color: Color(0xFF00E676)),
              filled: true,
              fillColor: const Color(0xFF0D0F17),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white24)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF00E676))),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'Device name is required';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                final id = _idController.text.trim();
                final name = _nameController.text.trim();
                await _saveDevice(id, name);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF00E676),
                    content: Text('Registered device "$name"', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                );
              }
            },
            icon: const Icon(Icons.save, size: 20),
            label: const Text('Save & Track Device', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
    );
  }

  /// Individual Tracked Device Card Tile
  Widget _buildTrackedDeviceTile(TrackedDevice device) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161A28),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.2),
            child: const Icon(Icons.bluetooth_searching, color: Color(0xFF00E676), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  device.id,
                  style: const TextStyle(color: Color(0xFF00E5FF), fontFamily: 'monospace', fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  'Added on: ${device.createdAt.year}-${device.createdAt.month.toString().padLeft(2, '0')}-${device.createdAt.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            tooltip: 'Unpair / Delete',
            onPressed: () => _confirmDeleteDevice(device),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDevice(TrackedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Unpair Device', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to stop tracking "${device.name}"? This will also remove its associated local location logs.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _storageService.deleteTrackedDevice(device.id, deleteLogs: true);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRegenerateIdDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Regenerate Self_ID?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Warning: Regenerating your cryptographic Self_ID will forge a new local UUID. Devices that paired with your previous ID will no longer recognize your beacon until re-paired.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await _storageService.regenerateSelfId();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF00E676),
                  content: Text('Generated brand new cryptographic Self_ID', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              );
            },
            child: const Text('Regenerate', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
