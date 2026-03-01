import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config/identity_ui_config.dart';
import '../theme.dart';
import '../utils/name_generator.dart';
import 'chat_screen.dart';

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key});

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  Future<List<Map<String, Object?>>>? _rowsFuture;
  int _lastUnreadSignature = -1;

  int _computeUnreadSignature(Map<String, int> unreadCounts) {
    final entries = unreadCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    final signature = _computeUnreadSignature(appState.unreadCounts);
    if (_rowsFuture == null || signature != _lastUnreadSignature) {
      _lastUnreadSignature = signature;
      _rowsFuture = appState.db.getRecentChatRows();
    }
  }

  Future<void> _reloadRows() async {
    final appState = Provider.of<AppState>(context, listen: false);
    setState(() {
      _rowsFuture = appState.db.getRecentChatRows();
    });
    await _rowsFuture;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final unreadCounts = appState.unreadCounts;
    final connectedPeerIds = appState.meshRouter.getConnectedPeerIds();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Messages',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.link_rounded), text: 'Direct'),
              Tab(icon: Icon(Icons.hub_rounded), text: 'Mesh'),
            ],
          ),
        ),
        body: FutureBuilder<List<Map<String, Object?>>>(
          future: _rowsFuture ?? appState.db.getRecentChatRows(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final rows = List<Map<String, Object?>>.from(
              snapshot.data ?? const [],
            );
            final existingPeerIds = <String>{
              for (final row in rows)
                if ((row['peer_id'] as String?) != null)
                  (row['peer_id'] as String?)!,
            };

            // If there are unread counters with no resolved row, surface a fallback row
            // so unread chats are still visible.
            for (final entry in unreadCounts.entries) {
              if (entry.value <= 0) continue;
              if (existingPeerIds.contains(entry.key)) continue;

              String displayName = '';
              int lastSeen = 0;
              for (final peer in appState.peers) {
                if (peer.id == entry.key) {
                  displayName = peer.displayName;
                  lastSeen = peer.lastSeen;
                  break;
                }
              }

              rows.add({
                'peer_id': entry.key,
                'last_content': '(new message)',
                'last_timestamp': 0,
                'is_sent_by_me': 0,
                'last_status': 0,
                'display_name': displayName,
                'address': '',
                'last_seen': lastSeen,
                'has_app': 0,
                'is_wifi': 0,
                'is_bluetooth': 0,
              });
              existingPeerIds.add(entry.key);
            }

            rows.sort((a, b) {
              final aPeerId = (a['peer_id'] as String?) ?? '';
              final bPeerId = (b['peer_id'] as String?) ?? '';
              final unreadA = unreadCounts[aPeerId] ?? 0;
              final unreadB = unreadCounts[bPeerId] ?? 0;
              if (unreadA != unreadB) {
                return unreadB.compareTo(unreadA);
              }
              final tsA = (a['last_timestamp'] as int?) ?? 0;
              final tsB = (b['last_timestamp'] as int?) ?? 0;
              return tsB.compareTo(tsA);
            });

            final directRows = <Map<String, Object?>>[];
            final meshRows = <Map<String, Object?>>[];
            for (final row in rows) {
              final peerId = (row['peer_id'] as String?) ?? '';
              if (peerId.isEmpty) continue;
              final isDirectSession = appState.isDirectSessionWithPeer(peerId);
              if (isDirectSession) {
                directRows.add(row);
              } else {
                meshRows.add(row);
              }
            }

            return TabBarView(
              children: [
                _buildRowsTab(
                  rows: directRows,
                  emptyTitle: 'No direct chats',
                  emptySubtitle:
                      'Shown only when both peers are in Direct profile and directly connected',
                  unreadCounts: unreadCounts,
                  connectedPeerIds: connectedPeerIds,
                  appState: appState,
                ),
                _buildRowsTab(
                  rows: meshRows,
                  emptyTitle: 'No mesh chats',
                  emptySubtitle: 'Offline or routed conversations appear here',
                  unreadCounts: unreadCounts,
                  connectedPeerIds: connectedPeerIds,
                  appState: appState,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRowsTab({
    required List<Map<String, Object?>> rows,
    required String emptyTitle,
    required String emptySubtitle,
    required Map<String, int> unreadCounts,
    required List<String> connectedPeerIds,
    required AppState appState,
  }) {
    if (rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: _reloadRows,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.62,
              child: Center(
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
                      emptyTitle,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        emptySubtitle,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reloadRows,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final peerId = (row['peer_id'] as String?) ?? '';
          if (peerId.isEmpty) return const SizedBox.shrink();

          final unreadCount = unreadCounts[peerId] ?? 0;
          final isConnected = connectedPeerIds.contains(peerId);

          final rawDisplayName = (row['display_name'] as String?) ?? '';
          String displayName = rawDisplayName.trim();
          if (displayName.isEmpty ||
              displayName == IdentityUiConfig.defaultDisplayName ||
              (displayName.length > 40 && displayName == peerId)) {
            displayName = NameGenerator.generateShortName(peerId);
          }

          final lastContent = (row['last_content'] as String?) ?? '';
          final initials = NameGenerator.generateInitials(peerId);
          final avatarHue = (peerId.hashCode % 360).abs().toDouble();
          final avatarColor =
              HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor();

          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(preselectedPeerId: peerId),
                    ),
                  );
                },
                onLongPress: () async {
                  final action = await showModalBottomSheet<String>(
                    context: context,
                    backgroundColor: AppTheme.bgSurface,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    builder: (sheetContext) => SafeArea(
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: const Text('Delete chat'),
                        subtitle: Text(displayName),
                        onTap: () => Navigator.pop(sheetContext, 'delete'),
                      ),
                    ),
                  );
                  if (action != 'delete' || !context.mounted) return;

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Delete chat?'),
                      content: Text(
                        'Delete all local messages with $displayName?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    await appState.db.deleteChatConversation(peerId);
                    await appState.refreshUnreadCounts();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Deleted chat with $displayName'),
                        ),
                      );
                    }
                    await _reloadRows();
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: unreadCount > 0
                        ? AppTheme.primary.withValues(alpha: 0.04)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
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
                            Text(
                              lastContent,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
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
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withValues(alpha: 0.4),
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
                          color: AppTheme.textSecondary.withValues(alpha: 0.4),
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

