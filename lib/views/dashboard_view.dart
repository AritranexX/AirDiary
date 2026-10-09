import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tracked_device.dart';
import '../services/anti_stalking_service.dart';
import '../services/broadcaster_service.dart';
import '../services/scanner_service.dart';
import '../services/separation_service.dart';
import '../services/storage_service.dart';
import 'anti_stalking_view.dart';
import 'lan_sync_view.dart';
import 'pair_view.dart';
import 'radar_view.dart';
import 'safe_zones_view.dart';
import 'timeline_view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final StorageService _storageService = StorageService();
  final BroadcasterService _broadcasterService = BroadcasterService();
  final ScannerService _scannerService = ScannerService();
  final SeparationService _separationService = SeparationService();
  final AntiStalkingService _antiStalkingService = AntiStalkingService();

  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _storageService.addListener(_onServiceUpdate);
    _broadcasterService.addListener(_onServiceUpdate);
    _scannerService.addListener(_onServiceUpdate);
    _separationService.addListener(_onServiceUpdate);
    _antiStalkingService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _storageService.removeListener(_onServiceUpdate);
    _broadcasterService.removeListener(_onServiceUpdate);
    _scannerService.removeListener(_onServiceUpdate);
    _separationService.removeListener(_onServiceUpdate);
    _antiStalkingService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _launchMap(double lat, double lng) async {
    final String urlStr;
    if (Platform.isIOS || Platform.isMacOS) {
      urlStr = 'https://maps.apple.com/?q=$lat,$lng';
    } else {
      urlStr = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    }
    final Uri url = Uri.parse(urlStr);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open maps application.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F17),
      body: IndexedStack(
        index: _selectedTabIndex,
        children: [
          _buildBelongingsTab(),
          const RadarView(),
          const TimelineView(),
          const AntiStalkingView(),
          const LanSyncView(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    final alertsCount = _separationService.activeAlerts.length;
    final rogueBeacons = _storageService.getRogueBeacons();
    final suspiciousCount = rogueBeacons.where((b) => !b.isDismissed && b.distinctClusterCount >= 2).length;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF131622),
        border: Border(top: BorderSide(color: Color(0xFF1E293B))),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: const Color(0xFF131622),
          indicatorColor: const Color(0xFF00E5FF).withAlpha(40),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF));
            }
            return const TextStyle(fontSize: 12, color: Colors.grey);
          }),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF00E5FF));
            }
            return const IconThemeData(color: Colors.grey);
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedTabIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedTabIndex = index);
          },
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: alertsCount > 0,
                label: Text('$alertsCount'),
                child: const Icon(Icons.devices),
              ),
              label: 'Belongings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.radar),
              label: 'Radar',
            ),
            const NavigationDestination(
              icon: Icon(Icons.timeline),
              label: 'Timeline',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: suspiciousCount > 0,
                backgroundColor: const Color(0xFFFF5252),
                label: Text('$suspiciousCount'),
                child: const Icon(Icons.security),
              ),
              label: 'Shield',
            ),
            const NavigationDestination(
              icon: Icon(Icons.wifi_tethering),
              label: 'LAN Sync',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBelongingsTab() {
    final devices = _storageService.getTrackedDevices();
    final alerts = _separationService.activeAlerts;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F17),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.track_changes, color: Color(0xFF00E676), size: 22),
            SizedBox(width: 8),
            Text('AirDiary', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)),
          ],
        ),
        backgroundColor: const Color(0xFF131622),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: Color(0xFF00E676)),
            tooltip: 'Geofenced Safe Zones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SafeZonesView()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF)),
            tooltip: 'Pair / Sync Code',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairView()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Separation Alerts Banner if active
          if (alerts.isNotEmpty) _buildSeparationBanner(alerts),

          // Broadcast / Passive Scanner Engine Control Bar
          _buildStatusEngineControls(),

          // Target Devices List / Grid
          Expanded(
            child: devices.isEmpty
                ? _buildEmptyState()
                : _buildTargetGrid(devices),
          ),
        ],
      ),
    );
  }

  Widget _buildSeparationBanner(List<SeparationAlert> alerts) {
    final firstAlert = alerts.first;

    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF7F1D1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF5252)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF5252), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Left-Behind Separation Alert (${alerts.length})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '"${firstAlert.device.name}" not seen for ${firstAlert.elapsedSinceLastSeen.inMinutes}m outside safe zones.',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SafeZonesView()),
              );
            },
            child: const Text('Zones', style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.radar, size: 80, color: Colors.white.withAlpha(25)),
          const SizedBox(height: 16),
          const Text(
            'No targets tracked.',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_link, color: Colors.black),
            label: const Text('Pair a Belonging', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairView()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusEngineControls() {
    final isBroadcasting = _broadcasterService.isBroadcasting;
    final isScanning = _scannerService.isScanning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF131622),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildEngineToggle(
            title: 'Beacon Broadcast',
            isActive: isBroadcasting,
            icon: Icons.bluetooth_connected,
            color: const Color(0xFF00E5FF),
            onTap: _broadcasterService.toggleBroadcasting,
          ),
          Container(width: 1, height: 36, color: Colors.white10),
          _buildEngineToggle(
            title: 'Passive Scanner',
            isActive: isScanning,
            icon: Icons.track_changes,
            color: const Color(0xFF00E676),
            onTap: _scannerService.toggleScanning,
          ),
        ],
      ),
    );
  }

  Widget _buildEngineToggle({
    required String title,
    required bool isActive,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? color : Colors.white30,
              size: 26,
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTargetGrid(List<TrackedDevice> devices) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 1;
        if (constraints.maxWidth > 600) crossAxisCount = 2;
        if (constraints.maxWidth > 900) crossAxisCount = 3;
        if (constraints.maxWidth > 1200) crossAxisCount = 4;

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.35,
            mainAxisExtent: 210,
          ),
          itemCount: devices.length,
          itemBuilder: (context, index) {
            return _buildTargetCard(devices[index]);
          },
        );
      },
    );
  }

  Widget _buildTargetCard(TrackedDevice device) {
    final latestLog = _storageService.getLatestLocationLog(device.id);
    final String timeAgo;
    if (latestLog != null) {
      final diff = DateTime.now().difference(latestLog.timestamp);
      if (diff.inMinutes < 1) {
        timeAgo = 'Just now';
      } else if (diff.inHours < 1) {
        timeAgo = '${diff.inMinutes}m ago';
      } else if (diff.inDays < 1) {
        timeAgo = '${diff.inHours}h ago';
      } else {
        timeAgo = '${diff.inDays}d ago';
      }
    } else {
      timeAgo = 'Never seen';
    }

    final hasLocation = latestLog != null && !latestLog.isDesktopProximity;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E2230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  device.name,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                color: const Color(0xFF2A2E40),
                onSelected: (val) {
                  if (val == 'delete') {
                    _showDeleteConfirmation(device);
                  } else if (val == 'simulate') {
                    _scannerService.simulateProximityEvent(device);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'simulate',
                    child: Text('Simulate Proximity', style: TextStyle(color: Colors.white)),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete Belonging', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'ID: ${device.id.substring(0, device.id.length > 8 ? 8 : device.id.length)}...',
            style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                latestLog != null ? Icons.sensors : Icons.sensors_off,
                color: latestLog != null ? const Color(0xFF00E676) : Colors.white24,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                timeAgo,
                style: TextStyle(
                  color: latestLog != null ? const Color(0xFF00E676) : Colors.white30,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (latestLog != null) ...[
            const SizedBox(height: 4),
            Text(
              latestLog.tag ?? 'Proximity Fix',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),

          // Action Toolbar: Radar / Timeline / Map
          Row(
            children: [
              // Radar Precision Finder Button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.radar, size: 14, color: Color(0xFF00E5FF)),
                  label: const Text('Radar', style: TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E5FF), width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RadarView(initialDevice: device),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Timeline Breadcrumbs Button
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timeline, size: 14, color: Color(0xFF00E676)),
                  label: const Text('Logs', style: TextStyle(fontSize: 11, color: Color(0xFF00E676))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF00E676), width: 0.8),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TimelineView(initialDevice: device),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 6),

              // Map Action Button
              if (hasLocation)
                IconButton(
                  icon: const Icon(Icons.map, size: 18, color: Color(0xFF00E5FF)),
                  tooltip: 'Open in Maps',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => _launchMap(latestLog.latitude, latestLog.longitude),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(TrackedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        title: const Text('Remove Belonging?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${device.name}" and erase its proximity logs from local storage? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _storageService.deleteTrackedDevice(device.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
