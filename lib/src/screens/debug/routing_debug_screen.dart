import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/route.dart' as mesh_route;
import '../../models/queued_message.dart';
import '../../services/message_queue.dart';

class RoutingDebugScreen extends StatefulWidget {
  const RoutingDebugScreen({super.key});

  @override
  State<RoutingDebugScreen> createState() => _RoutingDebugScreenState();
}

class _RoutingDebugScreenState extends State<RoutingDebugScreen> {
  List<mesh_route.Route> _routes = [];
  List<QueuedMessage> _queuedMessages = [];
  QueueStats? _queueStats;
  List<String> _connectedPeerIds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDebugData();
  }

  Future<void> _loadDebugData() async {
    setState(() => _isLoading = true);

    final appState = Provider.of<AppState>(context, listen: false);
    final router = appState.meshRouter;

    try {
      final routes = await router.routeManager.getAllRoutes();
      final queued = await router.messageQueue.getAllQueued();
      final stats = await router.messageQueue.getStats();
      final connected = router.getConnectedPeerIds();

      setState(() {
        _routes = routes;
        _queuedMessages = queued;
        _queueStats = stats;
        _connectedPeerIds = connected;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading debug data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mesh Debug'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _loadDebugData,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.alt_route), text: 'Routes'),
              Tab(icon: Icon(Icons.queue), text: 'Queue'),
              Tab(icon: Icon(Icons.wifi), text: 'Network'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildRoutesTab(),
                  _buildQueueTab(),
                  _buildNetworkTab(),
                ],
              ),
      ),
    );
  }

  // ─── Routes Tab ───────────────────────────────────────────────────────

  Widget _buildRoutesTab() {
    if (_routes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.alt_route, size: 64, color: Colors.grey),
            SizedBox(height: 12),
            Text('No routes discovered yet', style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 4),
            Text('Routes populate when peers communicate', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final route = _routes[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: route.isStale ? Colors.orange : Colors.green,
            child: Text('${route.hopCount}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text(
            'To: ${_shortenId(route.destinationPeerId)}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: Text(
            'Via: ${_shortenId(route.nextHopPeerId)} · Score: ${route.preferenceScore.toStringAsFixed(3)}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('✓${route.successCount}  ✗${route.failureCount}', style: const TextStyle(fontSize: 11)),
              Text(route.isStale ? 'STALE' : 'ACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: route.isStale ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Queue Tab ────────────────────────────────────────────────────────

  Widget _buildQueueTab() {
    return Column(
      children: [
        // Stats header
        if (_queueStats != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statChip('Total', _queueStats!.totalMessages, Colors.blue),
                _statChip('High', _queueStats!.highPriority, Colors.red),
                _statChip('Normal', _queueStats!.normalPriority, Colors.orange),
                _statChip('Low', _queueStats!.lowPriority, Colors.grey),
              ],
            ),
          ),
        // Message list
        Expanded(
          child: _queuedMessages.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Queue is empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 4),
                      Text('Messages queue when next hop is unreachable', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _queuedMessages.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final msg = _queuedMessages[index];
                    return ListTile(
                      leading: Icon(
                        Icons.mail_outline,
                        color: _priorityColor(msg.message.priority.index),
                      ),
                      title: Text(
                        'ID: ${_shortenId(msg.message.messageId)}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                      subtitle: Text(
                        'To: ${_shortenId(msg.nextHopPeerId)} · Attempts: ${msg.attemptCount}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        _priorityLabel(msg.message.priority.index),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _priorityColor(msg.message.priority.index),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─── Network Tab ──────────────────────────────────────────────────────

  Widget _buildNetworkTab() {
    final appState = Provider.of<AppState>(context, listen: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Local identity
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(appState.displayName),
              subtitle: Text(
                'ID: ${_shortenId(appState.meshRouter.localPeerId)}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Connected peers section
          Text(
            'Connected Peers (${_connectedPeerIds.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_connectedPeerIds.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.signal_wifi_off, color: Colors.grey),
                title: Text('No connected peers'),
                subtitle: Text('Ensure Bluetooth and WiFi are enabled'),
              ),
            )
          else
            ...List.generate(_connectedPeerIds.length, (i) {
              final peerId = _connectedPeerIds[i];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.green,
                    child: Icon(Icons.link, color: Colors.white, size: 18),
                  ),
                  title: Text(
                    _shortenId(peerId),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                  subtitle: const Text('Active connection'),
                ),
              );
            }),

          const SizedBox(height: 16),

          // Discovered peers section
          Text(
            'All Known Peers (${appState.peers.length})',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...appState.peers.map((peer) {
            final isConnected = _connectedPeerIds.contains(peer.id);
            final lastSeenAgo = DateTime.now().millisecondsSinceEpoch - peer.lastSeen;
            final minutes = (lastSeenAgo / 60000).floor();

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isConnected ? Colors.green : Colors.grey,
                  child: Text(
                    peer.displayName.isNotEmpty ? peer.displayName[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(peer.displayName),
                subtitle: Text(
                  '${_shortenId(peer.id)} · ${peer.hasApp ? "PeerChat" : "BT only"} · ${minutes}m ago',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Icon(
                  isConnected ? Icons.link : Icons.link_off,
                  color: isConnected ? Colors.green : Colors.grey,
                  size: 18,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  Widget _statChip(String label, int count, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$count', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  String _shortenId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 6)}';
  }

  Color _priorityColor(int priority) {
    switch (priority) {
      case 2: return Colors.red;
      case 1: return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _priorityLabel(int priority) {
    switch (priority) {
      case 2: return 'HIGH';
      case 1: return 'NORMAL';
      default: return 'LOW';
    }
  }
}
