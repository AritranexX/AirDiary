import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/location_log.dart';
import '../models/tracked_device.dart';
import '../services/storage_service.dart';

/// Interactive Historical Breadcrumb Timeline View
class TimelineView extends StatefulWidget {
  final TrackedDevice? initialDevice;

  const TimelineView({super.key, this.initialDevice});

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  final StorageService _storageService = StorageService();

  List<TrackedDevice> _devices = [];
  List<LocationLog> _logs = [];
  String? _selectedDeviceId; // null = All Devices

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.initialDevice?.id;
    _loadData();
  }

  void _loadData() {
    setState(() {
      _devices = _storageService.getTrackedDevices();
      _logs = _storageService.getLocationLogs();
    });
  }

  List<LocationLog> get _filteredLogs {
    List<LocationLog> list;
    if (_selectedDeviceId == null) {
      list = List.from(_logs);
    } else {
      list = _logs.where((l) => l.deviceId == _selectedDeviceId).toList();
    }
    // Sort descending by timestamp (newest first)
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  TrackedDevice? _findDevice(String deviceId) {
    for (final d in _devices) {
      if (d.id == deviceId) return d;
    }
    return null;
  }

  Future<void> _openMapUrl(double lat, double lng) async {
    if (lat == 0.0 && lng == 0.0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No GPS coordinate attached to this proximity ping.'),
            backgroundColor: Color(0xFF334155),
          ),
        );
      }
      return;
    }

    final Uri googleMapsUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      if (await canLaunchUrl(googleMapsUri)) {
        await launchUrl(googleMapsUri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch maps application';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open map: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  double _calculateDistanceMeters(double lat1, double lng1, double lat2, double lng2) {
    if ((lat1 == 0.0 && lng1 == 0.0) || (lat2 == 0.0 && lng2 == 0.0)) return 0.0;
    const double earthRadiusMeters = 6371000.0;
    final double dLat = (lat2 - lat1) * (math.pi / 180.0);
    final double dLng = (lng2 - lng1) * (math.pi / 180.0);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredLogs;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0E14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.timeline, color: Color(0xFF00E5FF)),
            SizedBox(width: 8),
            Text('Historical Breadcrumbs'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Timeline',
            onPressed: _loadData,
          ),
          if (filtered.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (val) async {
                if (val == 'clear_all') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF1E293B),
                      title: const Text('Clear Timeline History?'),
                      content: Text(
                        _selectedDeviceId == null
                            ? 'This will permanently wipe all stored breadcrumbs.'
                            : 'This will wipe breadcrumbs for this device only.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    if (_selectedDeviceId == null) {
                      await _storageService.clearAllLocationLogs();
                    } else {
                      await _storageService.clearLocationLogsForDevice(_selectedDeviceId!);
                    }
                    _loadData();
                  }
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Clear Breadcrumb Logs', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Device Filter Chips Bar
          _buildFilterBar(),

          // Summary Statistics Bar
          _buildSummaryBar(filtered),

          // Timeline Log List
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final log = filtered[index];
                      final nextLog = index < filtered.length - 1 ? filtered[index + 1] : null;
                      final distFromPrev = nextLog != null
                          ? _calculateDistanceMeters(
                              nextLog.latitude,
                              nextLog.longitude,
                              log.latitude,
                              log.longitude,
                            )
                          : 0.0;

                      return _buildTimelineCard(
                        log: log,
                        device: _findDevice(log.deviceId),
                        isFirst: index == 0,
                        isLast: index == filtered.length - 1,
                        distFromPrevMeters: distFromPrev,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('All Belongings (${_logs.length})'),
              selected: _selectedDeviceId == null,
              selectedColor: const Color(0xFF00E5FF).withAlpha(50),
              checkmarkColor: const Color(0xFF00E5FF),
              onSelected: (selected) {
                setState(() {
                  _selectedDeviceId = null;
                });
              },
            ),
          ),
          ..._devices.map((d) {
            final count = _logs.where((l) => l.deviceId == d.id).length;
            final isSelected = _selectedDeviceId == d.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('${d.name} ($count)'),
                selected: isSelected,
                selectedColor: const Color(0xFF00E676).withAlpha(50),
                checkmarkColor: const Color(0xFF00E676),
                onSelected: (selected) {
                  setState(() {
                    _selectedDeviceId = selected ? d.id : null;
                  });
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryBar(List<LocationLog> filtered) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.place, size: 16, color: Color(0xFF00E5FF)),
              const SizedBox(width: 6),
              Text(
                '${filtered.length} Recorded Fixes',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (filtered.isNotEmpty)
            Text(
              'Latest: ${DateFormat('MMM d, HH:mm').format(filtered.first.timestamp)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard({
    required LocationLog log,
    required TrackedDevice? device,
    required bool isFirst,
    required bool isLast,
    required double distFromPrevMeters,
  }) {
    final hasGps = log.latitude != 0.0 || log.longitude != 0.0;
    final timeStr = DateFormat('hh:mm:ss a').format(log.timestamp);
    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(log.timestamp);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Vertical timeline line with node indicator
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 2,
                  height: 16,
                  color: isFirst ? Colors.transparent : const Color(0xFF334155),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isFirst ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isFirst ? const Color(0xFF00E676) : const Color(0xFF00E5FF)).withAlpha(120),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast ? Colors.transparent : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ),

          // Content Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFirst ? const Color(0xFF00E676).withAlpha(100) : const Color(0xFF334155),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Belonging Name + Timestamp
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.devices,
                            size: 16,
                            color: isFirst ? const Color(0xFF00E676) : const Color(0xFF00E5FF),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            device?.name ?? 'Unknown Belonging',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF00E5FF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 10),

                  // Coordinates & Status Badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasGps
                              ? const Color(0xFF00E676).withAlpha(30)
                              : const Color(0xFF64748B).withAlpha(30),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: hasGps ? const Color(0xFF00E676).withAlpha(100) : const Color(0xFF64748B),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasGps ? Icons.gps_fixed : Icons.portable_wifi_off,
                              size: 12,
                              color: hasGps ? const Color(0xFF00E676) : const Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasGps
                                  ? '${log.latitude.toStringAsFixed(4)}°, ${log.longitude.toStringAsFixed(4)}°'
                                  : 'No GPS (Proximity Only)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: hasGps ? const Color(0xFF00E676) : const Color(0xFF94A3B8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          log.tag ?? 'Proximity Fix',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade300),
                        ),
                      ),
                      if (distFromPrevMeters > 5.0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            distFromPrevMeters >= 1000
                                ? '+${(distFromPrevMeters / 1000).toStringAsFixed(1)} km delta'
                                : '+${distFromPrevMeters.toStringAsFixed(0)} m delta',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF60A5FA)),
                          ),
                        ),
                    ],
                  ),

                  // Map Deep-Link Button
                  if (hasGps) ...[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _openMapUrl(log.latitude, log.longitude),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00E5FF).withAlpha(80)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, size: 14, color: Color(0xFF00E5FF)),
                            SizedBox(width: 6),
                            Text(
                              'Open in Google / Apple Maps',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF00E5FF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
            Icon(Icons.route, size: 72, color: Colors.grey.shade600),
            const SizedBox(height: 16),
            const Text(
              'No Historical Breadcrumbs Yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'As your AirDiary scanner encounters registered belongings, periodic 5-minute throttled location fixes will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      ),
    );
  }
}
