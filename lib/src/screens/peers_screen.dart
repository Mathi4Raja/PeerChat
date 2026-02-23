import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
import '../theme.dart';
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
          title: Text(
            'Peers & Discovery',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          bottom: TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.radar_rounded), text: 'Discovered'),
              Tab(icon: Icon(Icons.link_rounded), text: 'Connected'),
            ],
            indicatorWeight: 3,
            dividerColor: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        body: Consumer<AppState>(
          builder: (context, appState, _) {
            final connectedIds = appState.meshRouter.getConnectedPeerIds();
            final allActive = appState.activePeers;

            final connected = allActive.where((p) => connectedIds.contains(p.id)).toList();
            final unconnected = allActive.where((p) => !connectedIds.contains(p.id)).toList();

            return TabBarView(
              children: [
                _UnconnectedTab(peers: unconnected),
                _ConnectedTab(peers: connected),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.person_add_rounded),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.link_off_rounded,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No connected peers',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Peers appear after a successful handshake',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: peers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
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
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.radar_rounded,
                size: 48,
                color: AppTheme.textSecondary.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No discovered devices',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Connected peers are in the first tab',
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    final withApp = peers.where((p) => p.hasApp).toList();
    final withoutApp = peers.where((p) => !p.hasApp).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (withApp.isNotEmpty) ...[
          _sectionHeader('PEERCHAT DEVICES', Icons.verified_user_rounded, AppTheme.online, withApp.length),
          const SizedBox(height: 8),
          ...withApp.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PeerTile(peer: p, isConnected: false),
          )),
          const SizedBox(height: 16),
        ],
        if (withoutApp.isNotEmpty) ...[
          _sectionHeader('OTHER BLUETOOTH DEVICES', Icons.bluetooth_searching_rounded, AppTheme.warning, withoutApp.length),
          const SizedBox(height: 8),
          ...withoutApp.map((p) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _PeerTile(peer: p, isConnected: false),
          )),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: color,
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
    final String initials = NameGenerator.generateInitials(peer.id);

    final bool isWiFi = peer.isWiFi || peer.address.contains('.') || peer.address == 'mDNS';
    final bool isBT = peer.isBluetooth || peer.address.contains(':') || peer.address.startsWith('00:');

    // Status
    String statusLabel = 'Not Installed';
    Color statusColor = AppTheme.textSecondary;
    if (isConnected) {
      statusLabel = 'Active';
      statusColor = AppTheme.online;
    } else if (isVerified) {
      statusLabel = 'Installed';
      statusColor = AppTheme.accent;
    }

    // Avatar color from peer ID
    final avatarHue = (peer.id.hashCode % 360).abs().toDouble();
    final avatarColor = isConnected
        ? AppTheme.online
        : (isVerified
            ? HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor()
            : AppTheme.textSecondary);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isVerified
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatScreen(preselectedPeerId: peer.id)),
                );
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: isConnected
                ? AppTheme.online.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: avatarColor.withValues(alpha: 0.12),
                child: isVerified
                    ? Text(
                        initials,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: avatarColor,
                        ),
                      )
                    : Icon(
                        Icons.devices_other_rounded,
                        size: 18,
                        color: avatarColor,
                      ),
              ),
              const SizedBox(width: 12),

              // Name & address
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isWiFi) _badge(Icons.wifi_rounded, Colors.blue),
                        if (isBT) _badge(Icons.bluetooth_rounded, Colors.indigo),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            peer.address,
                            style: GoogleFonts.firaCode(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              if (isConnected)
                Icon(Icons.check_circle_rounded, color: AppTheme.online, size: 20)
              else if (isVerified)
                Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary.withValues(alpha: 0.4), size: 20)
              else
                Icon(Icons.help_outline_rounded, color: AppTheme.textSecondary.withValues(alpha: 0.3), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 11, color: color),
    );
  }
}
