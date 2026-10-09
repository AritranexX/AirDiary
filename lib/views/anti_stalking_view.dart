import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/rogue_beacon.dart';
import '../models/tracked_device.dart';
import '../services/anti_stalking_service.dart';
import '../services/storage_service.dart';

/// Anti-Stalking & Rogue Beacon Security Audit View
class AntiStalkingView extends StatefulWidget {
  const AntiStalkingView({super.key});

  @override
  State<AntiStalkingView> createState() => _AntiStalkingViewState();
}

class _AntiStalkingViewState extends State<AntiStalkingView> {
  final StorageService _storageService = StorageService();
  final AntiStalkingService _antiStalkingService = AntiStalkingService();

  List<RogueBeacon> _beacons = [];
  bool _shieldEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    setState(() {
      _beacons = _storageService.getRogueBeacons(includeDismissed: true);
      _shieldEnabled = _storageService.antiStalkingEnabled;
    });
  }

  Future<void> _dismissBeacon(RogueBeacon beacon) async {
    await _storageService.dismissRogueBeacon(beacon.signatureId);
    _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dismissed tracking alert for ${beacon.signatureId.substring(0, 8)}...')),
      );
    }
  }

  Future<void> _pairAsMyDevice(RogueBeacon beacon) async {
    final nameController = TextEditingController(text: 'My New Beacon');
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Claim as Your Belonging?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Give this beacon a recognizable label to register it into your tracked devices.'),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Belonging Name',
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Register Belonging', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final newDevice = TrackedDevice(
        id: beacon.signatureId,
        name: nameController.text.trim().isNotEmpty ? nameController.text.trim() : 'Registered Belonging',
      );
      await _storageService.saveTrackedDevice(newDevice);
      await _storageService.dismissRogueBeacon(beacon.signatureId);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registered "${newDevice.name}" to Tracked Belongings')),
        );
      }
    }
  }

  void _simulateRogueThreat() {
    _antiStalkingService.simulateRogueBeacon(clusterCount: 3);
    _loadData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Simulated suspicious 3-cluster rogue beacon!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final suspiciousCount = _beacons.where((b) => !b.isDismissed && (b.distinctClusterCount >= 3 || b.distinctClusterCount >= 2)).length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0E14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFFF5252)),
            SizedBox(width: 8),
            Text('Anti-Stalking Shield'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Shield Status Card
            _buildShieldHeaderCard(suspiciousCount),
            const SizedBox(height: 20),

            // Section Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ambient Beacons Log',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_beacons.length} Detected',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_beacons.isEmpty)
              _buildEmptyState()
            else
              ..._beacons.map((beacon) => _buildBeaconCard(beacon)),

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
                      Icon(Icons.bug_report, color: Color(0xFFFF5252), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Security Diagnostics & Testing',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Inject a simulated rogue beacon signature moving across 3 spatial coordinate clusters.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF5252).withAlpha(40),
                      foregroundColor: const Color(0xFFFF5252),
                      side: const BorderSide(color: Color(0xFFFF5252)),
                    ),
                    icon: const Icon(Icons.radar, size: 16),
                    label: const Text('Simulate Rogue Beacon Alert'),
                    onPressed: _simulateRogueThreat,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShieldHeaderCard(int suspiciousCount) {
    final hasThreat = suspiciousCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasThreat ? const Color(0xFF7F1D1D) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasThreat ? const Color(0xFFFF5252) : const Color(0xFF334155),
          width: hasThreat ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    hasThreat ? Icons.warning_amber_rounded : Icons.gpp_good,
                    color: hasThreat ? const Color(0xFFFF5252) : const Color(0xFF00E676),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hasThreat ? 'THREAT DETECTED ($suspiciousCount)' : 'Anti-Stalking Shield Active',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              Switch(
                value: _shieldEnabled,
                activeTrackColor: const Color(0xFF00E676),
                thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.black;
                  }
                  return Colors.grey;
                }),
                onChanged: (val) async {
                  await _storageService.setAntiStalkingEnabled(val);
                  setState(() => _shieldEnabled = val);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasThreat
                ? 'An un-paired Bluetooth beacon has been detected travelling with you across multiple distinct geographic locations.'
                : 'Passively monitors un-paired BLE devices in your vicinity. Flags any beacon moving alongside you over >150m and >15 minutes.',
            style: TextStyle(fontSize: 12, color: hasThreat ? Colors.white : Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBeaconCard(RogueBeacon beacon) {
    final isSuspicious = beacon.distinctClusterCount >= 3 ||
        (beacon.distinctClusterCount >= 2 &&
            beacon.lastSeen.difference(beacon.firstSeen).inMinutes >= 15);
    final isHighRisk = isSuspicious && !beacon.isDismissed;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighRisk ? const Color(0xFFFF5252) : const Color(0xFF334155),
          width: isHighRisk ? 1.5 : 1.0,
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
                  color: isHighRisk ? const Color(0xFFFF5252).withAlpha(40) : const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isHighRisk ? Icons.warning : Icons.bluetooth_searching,
                  color: isHighRisk ? const Color(0xFFFF5252) : const Color(0xFF00E5FF),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beacon ${beacon.signatureId.substring(0, math.min(12, beacon.signatureId.length))}...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      'Detected ${beacon.detectionCount} times across ${beacon.distinctClusterCount} locations',
                      style: TextStyle(
                        fontSize: 12,
                        color: isHighRisk ? const Color(0xFFFF5252) : Colors.grey.shade400,
                        fontWeight: isHighRisk ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (beacon.isDismissed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Dismissed', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Metadata Grid
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('First Seen', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      DateFormat('MMM d, HH:mm').format(beacon.firstSeen),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Last Seen', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      DateFormat('MMM d, HH:mm').format(beacon.lastSeen),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Time Span', style: TextStyle(fontSize: 10, color: Colors.grey)),
                    Text(
                      '${beacon.lastSeen.difference(beacon.firstSeen).inMinutes} mins',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Action Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!beacon.isDismissed)
                TextButton(
                  onPressed: () => _dismissBeacon(beacon),
                  child: const Text('Dismiss Alert', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676).withAlpha(40),
                  foregroundColor: const Color(0xFF00E676),
                  side: const BorderSide(color: Color(0xFF00E676)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.check_circle_outline, size: 14),
                label: const Text('Claim Device', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _pairAsMyDevice(beacon),
              ),
            ],
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
          Icon(Icons.verified_user, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          const Text(
            'No Suspicious Beacons Detected',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Your local environment is clear. Any un-paired beacon following you across multiple coordinate clusters will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
