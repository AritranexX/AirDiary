import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tracked_device.dart';
import '../services/broadcaster_service.dart';
import '../services/scanner_service.dart';
import '../services/storage_service.dart';
import 'pair_view.dart';

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final StorageService _storageService = StorageService();
  final BroadcasterService _broadcasterService = BroadcasterService();
  final ScannerService _scannerService = ScannerService();

  @override
  void initState() {
    super.initState();
    _storageService.addListener(_onServiceUpdate);
    _broadcasterService.addListener(_onServiceUpdate);
    _scannerService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _storageService.removeListener(_onServiceUpdate);
    _broadcasterService.removeListener(_onServiceUpdate);
    _scannerService.removeListener(_onServiceUpdate);
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
    final devices = _storageService.getTrackedDevices();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F17),
      appBar: AppBar(
        title: const Text('AirDiary', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)),
        backgroundColor: const Color(0xFF131622),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF)),
            tooltip: 'Pair / Sync',
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
          _buildStatusEngineControls(),
          Expanded(
            child: devices.isEmpty
                ? _buildEmptyState()
                : _buildTargetGrid(devices),
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
          Icon(Icons.radar, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text(
            'No targets tracked.',
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_link, color: Colors.black),
            label: const Text('Pair a Device', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          Container(width: 1, height: 40, color: Colors.white10),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? color : Colors.white30,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
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
        // Adaptive grid layout: span sizing based on available width
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
            childAspectRatio: 1.5,
            mainAxisExtent: 180, // Fixed height for exact scaling
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
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  device.name,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
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
                    child: Text('Delete Target', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID: ${device.id.substring(0, 8)}...',
            style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace'),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                latestLog != null ? Icons.sensors : Icons.sensors_off,
                color: latestLog != null ? const Color(0xFF00E676) : Colors.white24,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                timeAgo,
                style: TextStyle(
                  color: latestLog != null ? const Color(0xFF00E676) : Colors.white30,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (latestLog != null)
            Text(
              latestLog.tag ?? 'Unknown state',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (hasLocation)
                ElevatedButton.icon(
                  icon: const Icon(Icons.map, size: 16, color: Colors.black),
                  label: const Text('Map', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: () => _launchMap(latestLog.latitude, latestLog.longitude),
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.location_off, size: 16, color: Colors.white54),
                  label: const Text('No Map', style: TextStyle(color: Colors.white54)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  onPressed: null,
                ),
            ],
          )
        ],
      ),
    );
  }

  void _showDeleteConfirmation(TrackedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E2230),
        title: const Text('Abandon Target?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete device "${device.name}" and erase all associated proximity logs from local storage? This cannot be undone.',
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
