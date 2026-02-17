import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
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
    final totalPeers = appState.activePeers.length; // Only count active peers
    
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
                const Text('Peers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '$totalPeers total',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Peers with App Section (can be used as hops)
            if (peersWithApp.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text(
                    'With PeerChat App (${peersWithApp.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...peersWithApp.map((p) {
                final isConnected = connectedIds.contains(p.id);
                // Generate human-readable name from peer ID if it's a cryptographic key
                final displayName = p.id.length > 40 
                    ? NameGenerator.generateShortName(p.id)
                    : p.displayName;
                
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    Icons.phone_android,
                    color: isConnected ? Colors.green[700] : Colors.blue[700],
                    size: 20,
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    p.address,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isConnected ? Colors.green[50] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isConnected ? Colors.green[300]! : Colors.blue[300]!,
                      ),
                    ),
                    child: Text(
                      isConnected ? 'Active' : 'Available',
                      style: TextStyle(
                        fontSize: 11,
                        color: isConnected ? Colors.green[700] : Colors.blue[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  onTap: () {
                    // Navigate to chat screen with this peer selected
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(preselectedPeerId: p.id),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
            
            // Peers without App Section (Bluetooth-only, can't be hops)
            if (peersWithoutApp.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.bluetooth, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Bluetooth Only (${peersWithoutApp.length})',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...peersWithoutApp.map((p) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(Icons.phone_android, color: Colors.grey[500], size: 20),
                    title: Text(
                      p.displayName,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${p.address} • No app',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Text(
                        'Can\'t hop',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )),
            ],
            
            // No peers message
            if (totalPeers == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  'No peers discovered',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
