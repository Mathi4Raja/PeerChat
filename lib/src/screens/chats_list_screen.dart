import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
import '../theme.dart';
import '../utils/name_generator.dart';
import 'chat_screen.dart';

class ChatsListScreen extends StatelessWidget {
  const ChatsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final peers = appState.peersWithApp;
    final unreadCounts = appState.unreadCounts;

    // Sorting: peers with unread messages first, then by display name
    final sortedPeers = List<Peer>.from(peers);
    sortedPeers.sort((a, b) {
      final unreadA = unreadCounts[a.id] ?? 0;
      final unreadB = unreadCounts[b.id] ?? 0;
      if (unreadA != unreadB) {
        return unreadB.compareTo(unreadA);
      }
      return a.displayName.compareTo(b.displayName);
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: sortedPeers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPurple.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 48,
                      color: AppTheme.accentPurple.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No active chats',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Connect with peers to start chatting',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: sortedPeers.length,
              itemBuilder: (context, index) {
                final peer = sortedPeers[index];
                final unreadCount = unreadCounts[peer.id] ?? 0;
                final isConnected = appState.meshRouter
                    .getConnectedPeerIds()
                    .contains(peer.id);

                String displayName = peer.displayName;
                if (displayName == 'PeerChat User' ||
                    (displayName.length > 40 && displayName == peer.id)) {
                  displayName = NameGenerator.generateShortName(peer.id);
                }

                // Generate initials for the avatar
                final initials = NameGenerator.generateInitials(peer.id);

                // Deterministic avatar color from peer ID
                final avatarHue = (peer.id.hashCode % 360).abs().toDouble();
                final avatarColor = HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ChatScreen(preselectedPeerId: peer.id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: unreadCount > 0
                              ? AppTheme.primary.withValues(alpha: 0.04)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor:
                                      avatarColor.withValues(alpha: 0.15),
                                  child: Text(
                                    initials,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: avatarColor,
                                    ),
                                  ),
                                ),
                                if (isConnected)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: AppTheme.online,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: AppTheme.bgDeep,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.online
                                                .withValues(alpha: 0.5),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 14),

                            // Name & status
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: unreadCount > 0
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isConnected
                                              ? AppTheme.online
                                              : AppTheme.textSecondary
                                                  .withValues(alpha: 0.4),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isConnected ? 'Online' : 'Offline',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: isConnected
                                              ? AppTheme.online
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Unread badge
                            if (unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '$unreadCount',
                                  style: GoogleFonts.inter(
                                    color: AppTheme.bgDeep,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              Icon(
                                Icons.chevron_right_rounded,
                                color:
                                    AppTheme.textSecondary.withValues(alpha: 0.4),
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
