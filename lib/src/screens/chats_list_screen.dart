import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/peer.dart';
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
        title: const Text('Messages'),
      ),
      body: sortedPeers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No active chats found',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ensure peers are connected in the Discovery screen.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: sortedPeers.length,
              itemBuilder: (context, index) {
                final peer = sortedPeers[index];
                final unreadCount = unreadCounts[peer.id] ?? 0;
                final isConnected = appState.meshRouter.getConnectedPeerIds().contains(peer.id);
                
                // If identity name is very long (peerId), generate a short name for display
                // BUT prioritize the handshake name we saved in the DB
                String displayName = peer.displayName;
                if (displayName == 'PeerChat User' || 
                   (displayName.length > 40 && displayName == peer.id)) {
                  displayName = NameGenerator.generateShortName(peer.id);
                }

                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: isConnected ? Colors.green[100] : Colors.blue[100],
                        child: Icon(
                          Icons.person,
                          color: isConnected ? Colors.green[700] : Colors.blue[700],
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
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    displayName,
                    style: TextStyle(
                      fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    isConnected ? 'Connected' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: isConnected ? Colors.green[700] : Colors.grey[600],
                    ),
                  ),
                  trailing: unreadCount > 0
                      ? Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(preselectedPeerId: peer.id),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
