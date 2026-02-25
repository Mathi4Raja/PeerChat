import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
import '../theme.dart';
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

    return Container(
      decoration: AppTheme.glassCard(),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Discovered Devices',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$totalPeers active',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            Divider(color: Colors.white.withValues(alpha: 0.06), height: 24),

            // ─── SECTION: VERIFIED PEERS (WITH APP) ───
            if (peersWithApp.isNotEmpty) ...[
              _buildSectionHeader(
                context,
                title: 'PEERCHAT USERS',
                icon: Icons.verified_user_rounded,
                color: AppTheme.online,
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
                icon: Icons.bluetooth_searching_rounded,
                color: AppTheme.warning,
                count: peersWithoutApp.length,
              ),
              const SizedBox(height: 8),
              ...peersWithoutApp.map((p) => _buildPeerTile(context, p, false)),
              const SizedBox(height: 8),
            ],

            // No peers message
            if (totalPeers == 0)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        size: 40,
                        color: AppTheme.textSecondary.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Scanning for peers via WiFi & Bluetooth...',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      ),
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
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$title ($count)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeerTile(BuildContext context, Peer peer, bool isConnected) {
    final bool isVerified = peer.hasApp;
    String displayName = peer.displayName;
    if (displayName == 'PeerChat User' || 
       (displayName.length > 40 && displayName == peer.id)) {
      displayName = NameGenerator.generateShortName(peer.id);
    }
    final initials = NameGenerator.generateInitials(peer.id);

    final bool isWiFi = peer.address.contains('.') || peer.address == 'mDNS';
    final bool isBT = peer.address.contains(':') || peer.address.startsWith('00:');

    final avatarHue = (peer.id.hashCode % 360).abs().toDouble();
    final avatarColor = isConnected
        ? AppTheme.online
        : (isVerified
            ? HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor()
            : AppTheme.textSecondary);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: avatarColor.withValues(alpha: 0.12),
          child: isVerified
              ? Text(
                  initials,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: avatarColor,
                  ),
                )
              : Icon(Icons.devices_other_rounded, size: 16, color: avatarColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isWiFi) _buildTransportBadge(Icons.wifi_rounded, Colors.blue),
            if (isBT) _buildTransportBadge(Icons.bluetooth_rounded, Colors.indigo),
          ],
        ),
        subtitle: Text(
          peer.address,
          style: GoogleFonts.firaCode(
            fontSize: 10,
            color: AppTheme.textSecondary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isVerified
            ? Icon(
                isConnected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: isConnected ? AppTheme.online : AppTheme.textSecondary.withValues(alpha: 0.4),
                size: 18,
              )
            : Text(
                '?',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
        onTap: isVerified
            ? () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(preselectedPeerId: peer.id),
                  ),
                );
              }
            : null,
      ),
    );
  }

  Widget _buildTransportBadge(IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 10, color: color),
    );
  }
}
