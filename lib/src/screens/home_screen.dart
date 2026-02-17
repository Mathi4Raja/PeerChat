import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../widgets/identity_card.dart';
import '../widgets/peers_list.dart';
import '../widgets/mesh_status_card.dart';
import 'add_peer_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('PeerChat Secure'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh peers',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Refreshing peer discovery...'),
                  duration: Duration(seconds: 1),
                ),
              );
              await appState.refreshDiscovery();
            },
          ),
          IconButton(
            icon: const Icon(Icons.chat),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                IdentityCard(),
                const SizedBox(height: 16),
                const MeshStatusCard(),
                const SizedBox(height: 16),
                const PeersList(),
                const SizedBox(height: 80), // Space for FAB
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.person_add),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddPeerScreen()));
        },
      ),
    );
  }
}
