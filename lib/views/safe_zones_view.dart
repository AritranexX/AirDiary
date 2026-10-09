import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/safe_zone.dart';
import '../models/tracked_device.dart';
import '../services/separation_service.dart';
import '../services/storage_service.dart';

/// Geofenced Safe Zones & Left-Behind Separation Settings View
class SafeZonesView extends StatefulWidget {
  const SafeZonesView({super.key});

  @override
  State<SafeZonesView> createState() => _SafeZonesViewState();
}

class _SafeZonesViewState extends State<SafeZonesView> {
  final StorageService _storageService = StorageService();
  final SeparationService _separationService = SeparationService();

  List<SafeZone> _safeZones = [];
  bool _alertsEnabled = true;
  int _thresholdMinutes = 15;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchCurrentLocation();
  }

  void _loadData() {
    setState(() {
      _safeZones = _storageService.getSafeZones();
      _alertsEnabled = _storageService.separationAlertsEnabled;
      _thresholdMinutes = _storageService.separationThresholdMinutes;
    });
  }

  Future<void> _fetchCurrentLocation() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        );
        if (mounted) setState(() => _currentPosition = pos);
      }
    } catch (e) {
      debugPrint('[SafeZonesView] GPS location fetch error: $e');
    }
  }

  Future<void> _showAddSafeZoneDialog() async {
    final nameController = TextEditingController(text: 'Home');
    double radius = 100.0;
    double lat = _currentPosition?.latitude ?? 37.7749;
    double lng = _currentPosition?.longitude ?? -122.4194;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Row(
              children: [
                Icon(Icons.shield, color: Color(0xFF00E676)),
                SizedBox(width: 8),
                Text('Add Safe Zone', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Safe zones silence separation alerts while your belongings remain inside.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Zone Name (e.g. Home, Office)',
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Geofence Radius', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${radius.toInt()} meters', style: const TextStyle(color: Color(0xFF00E676))),
                    ],
                  ),
                  Slider(
                    value: radius,
                    min: 50.0,
                    max: 500.0,
                    divisions: 9,
                    activeColor: const Color(0xFF00E676),
                    onChanged: (val) => setDialogState(() => radius = val),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.my_location, size: 16, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Center: ${lat.toStringAsFixed(4)}°, ${lng.toStringAsFixed(4)}°',
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                onPressed: () {
                  if (nameController.text.trim().isNotEmpty) {
                    Navigator.pop(ctx, true);
                  }
                },
                child: const Text('Save Safe Zone', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final newZone = SafeZone(
        name: nameController.text.trim(),
        latitude: lat,
        longitude: lng,
        radiusMeters: radius,
      );
      await _storageService.saveSafeZone(newZone);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added Safe Zone "${newZone.name}" (${radius.toInt()}m)')),
        );
      }
    }
  }

  Future<void> _deleteSafeZone(SafeZone zone) async {
    await _storageService.deleteSafeZone(zone.id);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed Safe Zone "${zone.name}"')),
      );
    }
  }

  void _simulateAlert() {
    final devices = _storageService.getTrackedDevices();
    final targetDevice = devices.isNotEmpty
        ? devices.first
        : TrackedDevice(id: 'sim-device-01', name: 'AirDiary Keyring');
    _separationService.simulateSeparationAlert(targetDevice);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Simulated Left-Behind Separation Alert!')),
    );
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
            Icon(Icons.shield_outlined, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Safe Zones & Alerts'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt, color: Color(0xFF00E676)),
            tooltip: 'Add Safe Zone',
            onPressed: _showAddSafeZoneDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Settings Card
            _buildSettingsCard(),
            const SizedBox(height: 20),

            // Safe Zones Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Geofenced Safe Zones',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_safeZones.length} Registered',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_safeZones.isEmpty)
              _buildEmptyState()
            else
              ..._safeZones.map((zone) => _buildSafeZoneCard(zone)),

            const SizedBox(height: 24),

            // Simulation Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.science_outlined, color: Color(0xFFFFB300), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Offline Security Simulation',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Trigger a mock left-behind alert to test notification routing and safe zone logic.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB300).withAlpha(40),
                      foregroundColor: const Color(0xFFFFB300),
                      side: const BorderSide(color: Color(0xFFFFB300)),
                    ),
                    icon: const Icon(Icons.notifications_active, size: 16),
                    label: const Text('Simulate Separation Alert'),
                    onPressed: _simulateAlert,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.notifications_paused, color: Color(0xFF00E5FF), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Left-Behind Alerts',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              Switch(
                value: _alertsEnabled,
                activeTrackColor: const Color(0xFF00E676),
                thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.black;
                  }
                  return Colors.grey;
                }),
                onChanged: (val) async {
                  await _storageService.setSeparationAlertsEnabled(val);
                  setState(() => _alertsEnabled = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Notifies you if a registered item has not been in Bluetooth range for longer than the threshold when outside your safe zones.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Absence Threshold', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('$_thresholdMinutes minutes', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: _thresholdMinutes.toDouble(),
            min: 5.0,
            max: 60.0,
            divisions: 11,
            activeColor: const Color(0xFF00E676),
            onChanged: _alertsEnabled
                ? (val) async {
                    final mins = val.toInt();
                    await _storageService.setSeparationThresholdMinutes(mins);
                    setState(() => _thresholdMinutes = mins);
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSafeZoneCard(SafeZone zone) {
    bool isInside = false;
    double? currentDistance;
    if (_currentPosition != null) {
      currentDistance = zone.distanceTo(_currentPosition!.latitude, _currentPosition!.longitude);
      isInside = zone.contains(_currentPosition!.latitude, _currentPosition!.longitude);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInside ? const Color(0xFF00E676) : const Color(0xFF334155),
          width: isInside ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isInside ? const Color(0xFF00E676).withAlpha(40) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isInside ? Icons.verified_user : Icons.location_city,
                  color: isInside ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Radius: ${zone.radiusMeters.toInt()}m',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                tooltip: 'Delete Zone',
                onPressed: () => _deleteSafeZone(zone),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${zone.latitude.toStringAsFixed(4)}°, ${zone.longitude.toStringAsFixed(4)}°',
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey),
                ),
                if (currentDistance != null)
                  Text(
                    isInside
                        ? 'INSIDE ZONE (${currentDistance.toInt()}m from center)'
                        : '${(currentDistance / 1000).toStringAsFixed(1)} km away',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isInside ? const Color(0xFF00E676) : Colors.grey,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Icon(Icons.shield_moon_outlined, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          const Text(
            'No Safe Zones Registered',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Register Home, Office, or Work to prevent false left-behind alerts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            icon: const Icon(Icons.add_location, color: Colors.black),
            label: const Text('Add Current Location', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: _showAddSafeZoneDialog,
          ),
        ],
      ),
    );
  }
}
