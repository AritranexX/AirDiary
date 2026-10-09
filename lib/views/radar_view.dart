import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/tracked_device.dart';
import '../services/scanner_service.dart';
import '../services/storage_service.dart';

/// Real-Time RSSI Signal Radar & Hot/Cold Precision Finder View
class RadarView extends StatefulWidget {
  final TrackedDevice? initialDevice;

  const RadarView({super.key, this.initialDevice});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  final ScannerService _scannerService = ScannerService();

  late AnimationController _sweepController;
  StreamSubscription<LiveRssiEvent>? _rssiSubscription;

  List<TrackedDevice> _devices = [];
  TrackedDevice? _selectedDevice;

  int _rawRssi = -100;
  double _smoothedRssi = -100.0;
  double _estimatedDistance = 20.0;
  DateTime? _lastSignalTime;
  Timer? _decayTimer;

  // Smoothing constant for Exponential Weighted Moving Average (EWMA)
  static const double _alpha = 0.35;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _loadDevices();

    // Listen to high-frequency live RSSI stream
    _rssiSubscription = _scannerService.liveRssiStream.listen((event) {
      if (_selectedDevice != null && event.deviceId.toLowerCase() == _selectedDevice!.id.toLowerCase()) {
        _onRssiReceived(event.rssi);
      }
    });

    // Decay signal if no packets received for > 8 seconds
    _decayTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_lastSignalTime != null &&
          DateTime.now().difference(_lastSignalTime!) > const Duration(seconds: 8)) {
        if (mounted && _smoothedRssi > -95) {
          setState(() {
            _smoothedRssi = (_smoothedRssi - 3.0).clamp(-100.0, -30.0);
            _estimatedDistance = _computeDistance(_smoothedRssi);
          });
        }
      }
    });
  }

  void _loadDevices() {
    final devices = _storageService.getTrackedDevices();
    setState(() {
      _devices = devices;
      if (widget.initialDevice != null && devices.any((d) => d.id == widget.initialDevice!.id)) {
        _selectedDevice = widget.initialDevice;
      } else if (devices.isNotEmpty) {
        _selectedDevice = devices.first;
      }
    });
  }

  void _onRssiReceived(int rssi) {
    if (!mounted) return;
    setState(() {
      _rawRssi = rssi;
      _lastSignalTime = DateTime.now();
      if (_smoothedRssi <= -99) {
        _smoothedRssi = rssi.toDouble();
      } else {
        _smoothedRssi = (_alpha * rssi) + ((1.0 - _alpha) * _smoothedRssi);
      }
      _estimatedDistance = _computeDistance(_smoothedRssi);
    });
  }

  /// Log-distance path loss formula: distance = 10 ^ ((TxPower - RSSI) / (10 * n))
  double _computeDistance(double rssi) {
    const double txPowerAt1m = -59.0;
    const double n = 2.2;
    final exponent = (txPowerAt1m - rssi) / (10.0 * n);
    final dist = math.pow(10.0, exponent).toDouble();
    return dist.clamp(0.1, 30.0);
  }

  /// Heat status description based on smoothed RSSI
  String get _proximityStatus {
    if (_lastSignalTime == null) return 'Searching for BLE beacon...';
    if (_smoothedRssi >= -55) return 'BURNING HOT! (Immediate Proximity < 1m)';
    if (_smoothedRssi >= -68) return 'WARM (Nearby 1 - 3m)';
    if (_smoothedRssi >= -80) return 'COOL (Moderate Range 3 - 8m)';
    return 'COLD (Weak Signal > 8m)';
  }

  /// Dynamic color gradient from Cold (Blue) to Warm (Amber) to Hot (Emerald/Neon Green)
  Color get _proximityColor {
    if (_lastSignalTime == null) return const Color(0xFF64748B);
    if (_smoothedRssi >= -55) return const Color(0xFF00E676); // Emerald Green
    if (_smoothedRssi >= -68) return const Color(0xFFFFB300); // Amber
    if (_smoothedRssi >= -80) return const Color(0xFF00E5FF); // Cyan
    return const Color(0xFF3B82F6); // Blue
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _rssiSubscription?.cancel();
    _decayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0E14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.radar, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Precision Signal Radar'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Devices',
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _devices.isEmpty
          ? _buildEmptyState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 700;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: _buildRadarVisualizer()),
                      Expanded(flex: 2, child: _buildControlPanel()),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildRadarVisualizer(),
                      _buildControlPanel(),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_searching, size: 72, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            const Text(
              'No Tracked Devices Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Pair or register an AirDiary beacon first to use the precision radar finder.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadarVisualizer() {
    final radarRadius = 140.0;
    final normalizedSignal = ((_smoothedRssi + 100) / 70.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Target Device Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _proximityColor.withAlpha(128)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sensors, color: _proximityColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  _selectedDevice?.name ?? 'Select Device',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Circular Radar Graphic with CustomPainter
          SizedBox(
            width: radarRadius * 2 + 40,
            height: radarRadius * 2 + 40,
            child: AnimatedBuilder(
              animation: _sweepController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RadarPainter(
                    sweepAngle: _sweepController.value * 2 * math.pi,
                    proximityColor: _proximityColor,
                    signalNormalized: normalizedSignal,
                    hasSignal: _lastSignalTime != null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Proximity Status Banner
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: _proximityColor.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _proximityColor, width: 1.5),
            ),
            child: Column(
              children: [
                Text(
                  _proximityStatus,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _proximityColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                if (_lastSignalTime != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Last packet: ${DateTime.now().difference(_lastSignalTime!).inSeconds}s ago',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Selector
          const Text(
            'Target Belonging',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<TrackedDevice>(
                value: _selectedDevice,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E293B),
                items: _devices.map((d) {
                  return DropdownMenuItem(
                    value: d,
                    child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (device) {
                  setState(() {
                    _selectedDevice = device;
                    _rawRssi = -100;
                    _smoothedRssi = -100.0;
                    _lastSignalTime = null;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Signal Metrics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Signal Strength',
                  value: _lastSignalTime != null ? '${_smoothedRssi.toStringAsFixed(1)} dBm' : '-- dBm',
                  subtext: 'Raw: ${_rawRssi != -100 ? '$_rawRssi dBm' : '--'}',
                  icon: Icons.wifi,
                  color: _proximityColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  label: 'Est. Distance',
                  value: _lastSignalTime != null ? '~${_estimatedDistance.toStringAsFixed(1)} m' : '-- m',
                  subtext: _lastSignalTime != null
                      ? (_estimatedDistance < 1.0 ? 'Within arm reach' : 'Path loss 2.2n')
                      : 'Awaiting signal',
                  icon: Icons.straighten,
                  color: _proximityColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Proximity Meter Progress Bar
          const Text(
            'Proximity Heat Meter',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ((_smoothedRssi + 100) / 70.0).clamp(0.0, 1.0),
              minHeight: 16,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(_proximityColor),
            ),
          ),
          const SizedBox(height: 24),

          // Simulation & Test Triggers
          const Text(
            'Radar Signal Simulation',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPulseButton('Hot (-48 dBm)', -48),
              _buildPulseButton('Warm (-65 dBm)', -65),
              _buildPulseButton('Cool (-78 dBm)', -78),
              _buildPulseButton('Cold (-92 dBm)', -92),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseButton(String label, int rssi) {
    return ActionChip(
      avatar: const Icon(Icons.flash_on, size: 14, color: Color(0xFF00E676)),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: const Color(0xFF1E293B),
      side: const BorderSide(color: Color(0xFF334155)),
      onPressed: () {
        if (_selectedDevice != null) {
          _scannerService.simulateLiveRssi(_selectedDevice!.id, _selectedDevice!.name, rssi);
          _onRssiReceived(rssi);
        }
      },
    );
  }
}

/// CustomPainter for Circular Radar Sweep & Concentric Rings
class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final Color proximityColor;
  final double signalNormalized;
  final bool hasSignal;

  _RadarPainter({
    required this.sweepAngle,
    required this.proximityColor,
    required this.signalNormalized,
    required this.hasSignal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2 - 10;

    // Background circle
    final bgPaint = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, bgPaint);

    // Concentric Grid Rings
    final ringPaint = Paint()
      ..color = const Color(0xFF334155).withAlpha(150)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      final r = maxRadius * (i / 4.0);
      canvas.drawCircle(center, r, ringPaint);
    }

    // Crosshairs
    final crosshairPaint = Paint()
      ..color = const Color(0xFF334155).withAlpha(100)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(center.dx - maxRadius, center.dy), Offset(center.dx + maxRadius, center.dy), crosshairPaint);
    canvas.drawLine(Offset(center.dx, center.dy - maxRadius), Offset(center.dx, center.dy + maxRadius), crosshairPaint);

    // Rotating Radar Sweep Shader
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    final sweepGradient = SweepGradient(
      startAngle: 0.0,
      endAngle: math.pi / 2,
      colors: [
        proximityColor.withAlpha(0),
        proximityColor.withAlpha(120),
      ],
    );

    final sweepPaint = Paint()
      ..shader = sweepGradient.createShader(sweepRect)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sweepAngle);
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: maxRadius),
      -math.pi / 2,
      math.pi / 2,
      true,
      sweepPaint,
    );
    canvas.restore();

    // Signal Target Blip (Hot/Cold distance representation)
    if (hasSignal && signalNormalized > 0.05) {
      final blipDistance = maxRadius * (1.0 - (signalNormalized * 0.85));
      final blipAngle = sweepAngle - 0.4;
      final blipX = center.dx + blipDistance * math.cos(blipAngle);
      final blipY = center.dy + blipDistance * math.sin(blipAngle);

      // Blip Glow
      final glowPaint = Paint()
        ..color = proximityColor.withAlpha(100)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(Offset(blipX, blipY), 14, glowPaint);

      // Blip Core
      final blipPaint = Paint()
        ..color = proximityColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(blipX, blipY), 7, blipPaint);
    }

    // Center Device Anchor Icon
    final centerAnchorPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 5, centerAnchorPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.proximityColor != proximityColor ||
        oldDelegate.signalNormalized != signalNormalized ||
        oldDelegate.hasSignal != hasSignal;
  }
}
