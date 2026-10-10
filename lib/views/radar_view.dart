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

  // Calibration: calibrated 1-meter TxPower & environmental path-loss exponent
  double _txPowerAt1m = -59.0;
  double _pathLossN = 2.2;

  // Smoothing constant for Exponential Weighted Moving Average (EWMA)
  static const double _alpha = 0.35;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _scannerService.addListener(_onServiceUpdate);
    _loadDevices();

    // Auto-activate the passive scanner immediately upon entering the radar screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scannerService.isScanning) {
        _scannerService.startScanning();
      }
    });

    // Listen to high-frequency live RSSI stream
    _rssiSubscription = _scannerService.liveRssiStream.listen((event) {
      if (_selectedDevice != null &&
          _matchesSelectedDevice(event.deviceId)) {
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

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  bool _matchesSelectedDevice(String eventDeviceId) {
    final selected = _selectedDevice;
    if (selected == null) return false;
    final normalized = eventDeviceId.trim().toLowerCase();
    return normalized == selected.id.trim().toLowerCase() ||
        normalized == selected.name.trim().toLowerCase();
  }

  void _loadDevices() {
    final devices = _storageService.getTrackedDevices();
    setState(() {
      _devices = devices;
      if (widget.initialDevice != null &&
          devices.any((d) => d.id == widget.initialDevice!.id)) {
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
    final exponent = (_txPowerAt1m - rssi) / (10.0 * _pathLossN);
    final dist = math.pow(10.0, exponent).toDouble();
    return dist.clamp(0.1, 30.0);
  }

  /// Stable physical bearing (radians) derived deterministically from the
  /// target device identity so the blip rests at a fixed azimuth.
  double get _targetBearing {
    final id = _selectedDevice?.id ?? 'unknown';
    final sum = id.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return (sum % 360) * (math.pi / 180.0);
  }

  /// Phosphor illumination: brightest the instant the sweep arm crosses the
  /// target bearing, then decays exponentially until the arm returns.
  double _phosphorIllumination(double sweepAngle) {
    const twoPi = math.pi * 2;
    double delta = (sweepAngle - _targetBearing) % twoPi;
    if (delta < 0) delta += twoPi;
    final signalStrength = ((_smoothedRssi + 100) / 70.0).clamp(0.0, 1.0);
    return (math.exp(-delta * 1.5) + signalStrength * 0.08).clamp(0.0, 1.0);
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
    _scannerService.removeListener(_onServiceUpdate);
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
          // Live scanner status pill + toggle
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: _scannerService.toggleScanning,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _scannerService.isScanning
                      ? const Color(0xFF00E676).withAlpha(28)
                      : const Color(0xFF64748B).withAlpha(28),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _scannerService.isScanning
                        ? const Color(0xFF00E676)
                        : const Color(0xFF64748B),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _scannerService.isScanning
                          ? Icons.bluetooth_searching
                          : Icons.bluetooth_disabled,
                      size: 14,
                      color: _scannerService.isScanning
                          ? const Color(0xFF00E676)
                          : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _scannerService.isScanning ? 'LIVE' : 'STANDBY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _scannerService.isScanning
                            ? const Color(0xFF00E676)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
    final bearingDegrees = (_targetBearing * 180.0 / math.pi).round();

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
          const SizedBox(height: 8),

          // Fixed bearing readout
          Text(
            'Target Bearing: ${bearingDegrees.toString().padLeft(3, '0')}° (fixed azimuth)',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 16),

          // Circular Radar Graphic with CustomPainter
          SizedBox(
            width: radarRadius * 2 + 40,
            height: radarRadius * 2 + 40,
            child: AnimatedBuilder(
              animation: _sweepController,
              builder: (context, child) {
                final sweepAngle = _sweepController.value * 2 * math.pi;
                return CustomPaint(
                  painter: _RadarPainter(
                    sweepAngle: sweepAngle,
                    targetBearing: _targetBearing,
                    illumination: _phosphorIllumination(sweepAngle),
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
                      ? (_estimatedDistance < 1.0 ? 'Within arm reach' : 'Path loss ${_pathLossN.toStringAsFixed(1)}n')
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
          const SizedBox(height: 20),

          // Calibration Section
          const Text(
            'Signal Calibration',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TxPower @1m', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    Text('${_txPowerAt1m.toStringAsFixed(1)} dBm',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontFamily: 'monospace')),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00E5FF),
                    thumbColor: const Color(0xFF00E5FF),
                    overlayColor: const Color(0xFF00E5FF).withAlpha(40),
                  ),
                  child: Slider(
                    value: _txPowerAt1m,
                    min: -80,
                    max: -30,
                    divisions: 50,
                    onChanged: (val) {
                      setState(() {
                        _txPowerAt1m = val;
                        if (_lastSignalTime != null) {
                          _estimatedDistance = _computeDistance(_smoothedRssi);
                        }
                      });
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Path-loss exponent (n)', style: TextStyle(fontSize: 12, color: Colors.white70)),
                    Text(_pathLossN.toStringAsFixed(2),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontFamily: 'monospace')),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00E5FF),
                    thumbColor: const Color(0xFF00E5FF),
                    overlayColor: const Color(0xFF00E5FF).withAlpha(40),
                  ),
                  child: Slider(
                    value: _pathLossN,
                    min: 1.5,
                    max: 3.5,
                    divisions: 40,
                    onChanged: (val) {
                      setState(() {
                        _pathLossN = val;
                        if (_lastSignalTime != null) {
                          _estimatedDistance = _computeDistance(_smoothedRssi);
                        }
                      });
                    },
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _txPowerAt1m = -59.0;
                        _pathLossN = 2.2;
                        if (_lastSignalTime != null) {
                          _estimatedDistance = _computeDistance(_smoothedRssi);
                        }
                      });
                    },
                    icon: const Icon(Icons.restore, size: 14, color: Color(0xFF00E5FF)),
                    label: const Text('Factory Defaults', style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

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
  final double targetBearing;
  final double illumination;
  final Color proximityColor;
  final double signalNormalized;
  final bool hasSignal;

  _RadarPainter({
    required this.sweepAngle,
    required this.targetBearing,
    required this.illumination,
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

    // Sweep arm leading edge line
    final armPaint = Paint()
      ..color = proximityColor.withAlpha(90)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center,
      Offset(
        center.dx + maxRadius * math.cos(sweepAngle - math.pi / 2),
        center.dy + maxRadius * math.sin(sweepAngle - math.pi / 2),
      ),
      armPaint,
    );

    // Fixed-bearing target blip with phosphor illumination decay
    if (hasSignal && signalNormalized > 0.05) {
      final blipDistance = maxRadius * (1.0 - (signalNormalized * 0.85));
      final blipAngle = targetBearing; // FIXED bearing — decoupled from sweep arm
      final blipX = center.dx + blipDistance * math.cos(blipAngle);
      final blipY = center.dy + blipDistance * math.sin(blipAngle);

      // Bearing spoke when illuminated
      if (illumination > 0.35) {
        final spokePaint = Paint()
          ..color = proximityColor.withAlpha((60 * illumination).round())
          ..strokeWidth = 1.0;
        canvas.drawLine(center, Offset(blipX, blipY), spokePaint);
      }

      // Phosphor glow halo — intensity follows illumination decay
      final glowPaint = Paint()
        ..color = proximityColor.withAlpha((140 * illumination).round())
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 8 * illumination);
      canvas.drawCircle(
        Offset(blipX, blipY),
        10 + 6 * illumination,
        glowPaint,
      );

      // Blip core — alpha fades with phosphor decay
      final blipPaint = Paint()
        ..color = proximityColor.withAlpha((255 * (0.25 + 0.75 * illumination)).round())
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(blipX, blipY), 5 + 3 * illumination, blipPaint);

      // Blip inner highlight
      final corePaint = Paint()
        ..color = Colors.white.withAlpha((200 * illumination).round())
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(blipX, blipY), 2.5, corePaint);
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
        oldDelegate.targetBearing != targetBearing ||
        oldDelegate.illumination != illumination ||
        oldDelegate.proximityColor != proximityColor ||
        oldDelegate.signalNormalized != signalNormalized ||
        oldDelegate.hasSignal != hasSignal;
  }
}
