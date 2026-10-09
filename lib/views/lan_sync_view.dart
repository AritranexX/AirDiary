import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lan_peer.dart';
import '../services/lan_sync_service.dart';

/// Zero-Cloud Local LAN Direct Socket P2P Sync View
class LanSyncView extends StatefulWidget {
  const LanSyncView({super.key});

  @override
  State<LanSyncView> createState() => _LanSyncViewState();
}

class _LanSyncViewState extends State<LanSyncView> {
  final LanSyncService _lanSyncService = LanSyncService();

  final TextEditingController _ipController = TextEditingController();
  bool _isManualSyncing = false;
  String? _syncingPeerId;

  @override
  void initState() {
    super.initState();
    _lanSyncService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _lanSyncService.removeListener(_onServiceUpdate);
    _ipController.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _syncWithPeer(LanPeer peer) async {
    setState(() => _syncingPeerId = peer.selfId);
    final result = await _lanSyncService.syncWithPeer(peer);
    if (mounted) {
      setState(() => _syncingPeerId = null);
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00E676),
            content: Text(
              'Success: Synced ${result.syncedDevicesCount} devices & ${result.syncedLogsCount} logs with ${peer.deviceName}!',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Sync Error: ${result.errorMessage ?? "Unknown socket failure"}'),
          ),
        );
      }
    }
  }

  Future<void> _syncWithManualIp() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    final manualPeer = LanPeer(
      ip: ip,
      port: LanSyncService.defaultPort,
      selfId: 'manual-$ip',
      deviceName: 'Manual IP ($ip)',
      lastSeen: DateTime.now(),
    );

    setState(() => _isManualSyncing = true);
    final result = await _lanSyncService.syncWithPeer(manualPeer);
    if (mounted) {
      setState(() => _isManualSyncing = false);
      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF00E676),
            content: Text(
              'Synced ${result.syncedDevicesCount} devices & ${result.syncedLogsCount} logs via $ip',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to connect to $ip:${LanSyncService.defaultPort}: ${result.errorMessage}'),
          ),
        );
      }
    }
  }

  void _simulatePeer() {
    _lanSyncService.simulatePeer(
      name: 'AirDiary MacBook Pro Node',
      ip: '192.168.1.188',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Simulated Wi-Fi peer discovered on local subnet.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final peers = _lanSyncService.discoveredPeers;
    final lastResult = _lanSyncService.lastSyncResult;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0E14) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.wifi_tethering, color: Color(0xFF00E5FF)),
            SizedBox(width: 8),
            Text('Zero-Cloud LAN P2P Sync'),
          ],
        ),
        actions: [
          IconButton(
            icon: _lanSyncService.isDiscovering
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                  )
                : const Icon(Icons.wifi_find),
            tooltip: 'Broadcast UDP Ping',
            onPressed: () => _lanSyncService.broadcastDiscoveryPing(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Engine Status Card
            _buildEngineStatusCard(),
            const SizedBox(height: 16),

            // Last Sync Result Banner
            if (lastResult != null) ...[
              _buildLastResultBanner(lastResult),
              const SizedBox(height: 16),
            ],

            // Discovered Peers Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Local Wi-Fi Nodes',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${peers.length} Discovered',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (peers.isEmpty)
              _buildEmptyPeersState()
            else
              ...peers.map((peer) => _buildPeerCard(peer)),

            const SizedBox(height: 24),

            // Direct IP Connect Section
            _buildDirectIpSection(),
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
                      Icon(Icons.devices, color: Color(0xFF00E5FF), size: 20),
                      SizedBox(width: 8),
                      Text(
                        'P2P Offline Verification',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Spawn a simulated peer node on the local subnet to verify delta sync and record union merging.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF).withAlpha(40),
                      foregroundColor: const Color(0xFF00E5FF),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                    ),
                    icon: const Icon(Icons.hub, size: 16),
                    label: const Text('Simulate Wi-Fi Peer Node'),
                    onPressed: _simulatePeer,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineStatusCard() {
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
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00E676),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Direct Socket P2P Protocol',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Port 41820',
                  style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF00E5FF)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lanSyncService.statusMessage,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          const Text(
            'Syncs belonging registries and location breadcrumbs between your phones, tablets, and laptops over the local Wi-Fi router. 100% offline with zero cloud servers or accounts.',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildLastResultBanner(LanSyncResult result) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isSuccess ? const Color(0xFF00E676).withAlpha(30) : Colors.redAccent.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.isSuccess ? Icons.check_circle : Icons.error_outline,
            color: result.isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.isSuccess
                      ? 'Last Sync: ${result.syncedDevicesCount} devices & ${result.syncedLogsCount} logs merged'
                      : 'Sync Failed: ${result.errorMessage ?? "Unknown error"}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: result.isSuccess ? const Color(0xFF00E676) : Colors.redAccent,
                  ),
                ),
                Text(
                  'Peer: ${result.peerName} (${result.peerIp}) · ${DateFormat('HH:mm:ss').format(result.timestamp)}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeerCard(LanPeer peer) {
    final isSyncing = _syncingPeerId == peer.selfId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.laptop_chromebook, color: Color(0xFF00E5FF), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  '${peer.ip}:${peer.port}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey),
                ),
                Text(
                  'Last seen: ${DateTime.now().difference(peer.lastSeen).inSeconds}s ago',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            icon: isSyncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.sync, size: 16),
            label: Text(
              isSyncing ? 'Syncing...' : 'Sync Now',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            onPressed: isSyncing ? null : () => _syncWithPeer(peer),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectIpSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Direct IP Connect',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          const Text(
            'If UDP broadcast discovery is blocked on your router, connect directly to the peer IP address:',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  decoration: InputDecoration(
                    hintText: 'e.g. 192.168.1.150',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                icon: _isManualSyncing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send, size: 16),
                label: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _isManualSyncing ? null : _syncWithManualIp,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPeersState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          Icon(Icons.wifi_find, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 12),
          const Text(
            'Listening for Local Wi-Fi Peers...',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Open AirDiary on another device connected to this Wi-Fi network to automatically discover and sync.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: Colors.black),
            icon: const Icon(Icons.radar),
            label: const Text('Broadcast Discovery Ping', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _lanSyncService.broadcastDiscoveryPing(),
          ),
        ],
      ),
    );
  }
}
