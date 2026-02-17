import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
import '../utils/name_generator.dart';
import 'add_peer_screen.dart';
import 'chat_screen.dart';

class PeersScreen extends StatelessWidget {
  const PeersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Peers & Discovery'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.link), text: 'Connected'),
              Tab(icon: Icon(Icons.radar), text: 'Unconnected'),
            ],
          ),
        ),
        body: Consumer<AppState>(
          builder: (context, appState, _) {
            final connectedIds = appState.meshRouter.getConnectedPeerIds();
            final allActive = appState.activePeers;

            // Connected = peers with completed handshake (in connectedIds)
            final connected = allActive.where((p) => connectedIds.contains(p.id)).toList();

            // Unconnected = all active peers NOT in the connected set
            final unconnected = allActive.where((p) => !connectedIds.contains(p.id)).toList();

            return TabBarView(
              children: [
                _ConnectedTab(peers: connected),
                _UnconnectedTab(peers: unconnected),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.person_add),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddPeerScreen()),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1: Connected Peers
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectedTab extends StatelessWidget {
  final List<Peer> peers;
  const _ConnectedTab({required this.peers});

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No connected peers', style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 4),
            Text('Peers appear here after a successful handshake',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: peers.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) => _PeerTile(
        peer: peers[index],
        isConnected: true,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2: Unconnected Peers
// ─────────────────────────────────────────────────────────────────────────────

class _UnconnectedTab extends StatelessWidget {
  final List<Peer> peers;
  const _UnconnectedTab({required this.peers});

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No unconnected devices', style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 4),
            Text('Connected peers are listed in the first tab',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    // Split into app vs no-app
    final withApp = peers.where((p) => p.hasApp).toList();
    final withoutApp = peers.where((p) => !p.hasApp).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (withApp.isNotEmpty) ...[
          _sectionHeader('PEERCHAT DEVICES', Icons.verified_user, Colors.green.shade700, withApp.length),
          const SizedBox(height: 4),
          ...withApp.map((p) => _PeerTile(peer: p, isConnected: false)),
          const SizedBox(height: 16),
        ],
        if (withoutApp.isNotEmpty) ...[
          _sectionHeader('OTHER BLUETOOTH DEVICES', Icons.bluetooth_searching, Colors.orange.shade800, withoutApp.length),
          const SizedBox(height: 4),
          ...withoutApp.map((p) => _PeerTile(peer: p, isConnected: false)),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold,
              letterSpacing: 1.1, color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared peer tile widget
// ─────────────────────────────────────────────────────────────────────────────

class _PeerTile extends StatelessWidget {
  final Peer peer;
  final bool isConnected;
  const _PeerTile({required this.peer, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final bool isVerified = peer.hasApp;
    final String displayName = peer.id.length > 40
        ? NameGenerator.generateShortName(peer.id)
        : peer.displayName;

    final bool isWiFi = peer.isWiFi || peer.address.contains('.') || peer.address == 'mDNS';
    final bool isBT = peer.isBluetooth || peer.address.contains(':') || peer.address.startsWith('00:');

    // App Status Label
    String statusLabel = 'Not Installed';
    Color statusColor = Colors.grey.shade600;
    if (isConnected) {
      statusLabel = 'Active';
      statusColor = Colors.green.shade700;
    } else if (isVerified) {
      statusLabel = 'Installed';
      statusColor = Colors.blue.shade700;
    }

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isConnected
            ? Colors.green.shade100
            : (isVerified ? Colors.blue.shade100 : Colors.grey.shade200),
        child: Icon(
          isConnected ? Icons.link : (isVerified ? Icons.person : Icons.devices_other),
          size: 20,
          color: isConnected
              ? Colors.green.shade700
              : (isVerified ? Colors.blue.shade700 : Colors.grey.shade600),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Show both if discovered via both
          if (isWiFi) _badge(Icons.wifi, 'WiFi', Colors.blue),
          if (isBT) _badge(Icons.bluetooth, 'BT', Colors.indigo),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              peer.address,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
      trailing: isConnected
          ? Icon(Icons.check_circle, color: Colors.green.shade700, size: 20)
          : (isVerified
              ? Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20)
              : const Icon(Icons.help_outline, color: Colors.grey, size: 16)),
      onTap: isVerified
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChatScreen(preselectedPeerId: peer.id)),
              );
            }
          : null,
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
