import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
import '../utils/name_generator.dart';
import '../screens/chat_screen.dart';

class PeersList extends StatelessWidget {
  const PeersList({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final peersWithApp = appState.peersWithApp;
    final peersWithoutApp = appState.peersWithoutApp;
    final connectedIds = appState.meshRouter.getConnectedPeerIds();
    final totalPeers = appState.activePeers.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Discovered Devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '$totalPeers active',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            const Divider(),

            // ─── SECTION: VERIFIED PEERS (WITH APP) ───
            if (peersWithApp.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: 'PEERCHAT USERS',
                icon: Icons.verified_user,
                color: Colors.green[700]!,
                count: peersWithApp.length,
              ),
              const SizedBox(height: 8),
              ...peersWithApp.map((p) => _buildPeerTile(context, p, connectedIds.contains(p.id))),
              const SizedBox(height: 16),
            ],

            // ─── SECTION: UNVERIFIED DEVICES (RAW) ───
            if (peersWithoutApp.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: 'UNVERIFIED DEVICES',
                icon: Icons.bluetooth_searching,
                color: Colors.orange[800]!,
                count: peersWithoutApp.length,
              ),
              const SizedBox(height: 8),
              ...peersWithoutApp.map((p) => _buildPeerTile(context, p, false)),
              const SizedBox(height: 8),
            ],

            // No peers message
            if (totalPeers == 0)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Column(
                    children: [
                      Icon(Icons.radar, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Scanning for peers via WiFi & Bluetooth...',
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context,
      {required String title, required IconData icon, required Color color, required int count}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          '$title ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPeerTile(BuildContext context, Peer peer, bool isConnected) {
    final bool isVerified = peer.hasApp;
    // If identity name is very long (peerId), generate a short name for display
    // BUT prioritize the handshake name we saved in the DB
    String displayName = peer.displayName;
    if (displayName == 'PeerChat User' || 
       (displayName.length > 40 && displayName == peer.id)) {
      displayName = NameGenerator.generateShortName(peer.id);
    }

    // Detect transport from address/ID logic
    final bool isWiFi = peer.address.contains('.') || peer.address == 'mDNS';
    final bool isBT = peer.address.contains(':') || peer.address.startsWith('00:');

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isVerified 
            ? (isConnected ? Colors.green[100] : Colors.blue[100])
            : Colors.grey[200],
        child: Icon(
          isVerified ? Icons.person : Icons.devices_other,
          size: 20,
          color: isVerified 
              ? (isConnected ? Colors.green[700] : Colors.blue[700])
              : Colors.grey[600],
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
          if (isWiFi) _buildTransportBadge(Icons.wifi, 'WiFi', Colors.blue),
          if (isBT) _buildTransportBadge(Icons.bluetooth, 'BT', Colors.indigo),
        ],
      ),
      subtitle: Text(
        peer.address,
        style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isVerified
          ? Icon(
              isConnected ? Icons.link : Icons.chevron_right,
              color: isConnected ? Colors.green[700] : Colors.grey[400],
              size: 20,
            )
          : const Text('?', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
      onTap: isVerified
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(preselectedPeerId: peer.id),
                ),
              );
            }
          : null,
    );
  }

  Widget _buildTransportBadge(IconData icon, String label, Color color) {
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
          Text(
            label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
