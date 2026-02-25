import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/route.dart' as mesh_route;
import '../../models/queued_message.dart';
import '../../services/message_queue.dart';
import '../../services/mesh_router_service.dart';
import '../../theme.dart';

class RoutingDebugScreen extends StatefulWidget {
  const RoutingDebugScreen({super.key});

  @override
  State<RoutingDebugScreen> createState() => _RoutingDebugScreenState();
}

class _RoutingDebugScreenState extends State<RoutingDebugScreen> {
  List<mesh_route.Route> _routes = [];
  List<QueuedMessage> _queuedMessages = [];
  QueueStats? _queueStats;
  RoutingStats? _routingStats;
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
      final routingStats = await router.stats;
      final connected = router.getConnectedPeerIds();

      setState(() {
        _routes = routes;
        _queuedMessages = queued;
        _queueStats = stats;
        _routingStats = routingStats;
        _connectedPeerIds = connected;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading debug data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cleanupStaleData() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final stats = await appState.clearStaleNetworkData(
      stalePeerAge: const Duration(minutes: 30),
      staleRouteAge: const Duration(minutes: 30),
      staleEndpointAge: const Duration(hours: 2),
    );
    if (!mounted) return;
    final removedPeers = stats['removed_peers'] ?? 0;
    final removedRoutes = (stats['removed_routes_by_age'] ?? 0) +
        (stats['removed_routes_via_stale_peers'] ?? 0);
    final removedQueue = stats['removed_queue_via_stale_peers'] ?? 0;
    final removedEndpoints = stats['removed_known_endpoints'] ?? 0;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cleanup done: peers=$removedPeers routes=$removedRoutes queue=$removedQueue endpoints=$removedEndpoints',
        ),
      ),
    );
    await _loadDebugData();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Mesh Debug',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.cleaning_services_rounded),
              tooltip: 'Cleanup stale data',
              onPressed: _cleanupStaleData,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: _loadDebugData,
            ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.alt_route_rounded), text: 'Routes'),
              Tab(icon: Icon(Icons.queue_rounded), text: 'Queue'),
              Tab(icon: Icon(Icons.wifi_rounded), text: 'Network'),
            ],
            indicatorWeight: 3,
            dividerColor: Colors.white.withValues(alpha: 0.06),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
              child: Icon(Icons.alt_route_rounded, size: 48, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
            ),
            const SizedBox(height: 16),
            Text('No routes discovered', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Routes populate when peers communicate', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _routes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final route = _routes[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: route.isStale
                ? AppTheme.warning.withValues(alpha: 0.04)
                : AppTheme.online.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: route.isStale
                  ? AppTheme.warning.withValues(alpha: 0.15)
                  : AppTheme.online.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: (route.isStale ? AppTheme.warning : AppTheme.online).withValues(alpha: 0.15),
                child: Text(
                  '${route.hopCount}',
                  style: GoogleFonts.inter(
                    color: route.isStale ? AppTheme.warning : AppTheme.online,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'To: ${_shortenId(route.destinationPeerId)}',
                      style: GoogleFonts.firaCode(fontSize: 12, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Via: ${_shortenId(route.nextHopPeerId)} · Score: ${route.preferenceScore.toStringAsFixed(3)}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '✓${route.successCount}  ✗${route.failureCount}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (route.isStale ? AppTheme.warning : AppTheme.online).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      route.isStale ? 'STALE' : 'ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: route.isStale ? AppTheme.warning : AppTheme.online,
                      ),
                    ),
                  ),
                ],
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
            color: AppTheme.bgSurface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statChip('Total', _queueStats!.totalMessages, AppTheme.accent),
                _statChip('High', _queueStats!.highPriority, AppTheme.danger),
                _statChip('Normal', _queueStats!.normalPriority, AppTheme.warning),
                _statChip('Low', _queueStats!.lowPriority, AppTheme.textSecondary),
              ],
            ),
          ),
        // Message list
        Expanded(
          child: _queuedMessages.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.online.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check_circle_outline_rounded, size: 48, color: AppTheme.online.withValues(alpha: 0.4)),
                      ),
                      const SizedBox(height: 16),
                      Text('Queue is empty', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Messages queue when next hop is unreachable', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _queuedMessages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final msg = _queuedMessages[index];
                    final priorityColor = _priorityColor(msg.message.priority.index);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: priorityColor.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: priorityColor.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.mail_outline_rounded, color: priorityColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID: ${_shortenId(msg.message.messageId)}',
                                  style: GoogleFonts.firaCode(fontSize: 12, color: AppTheme.textPrimary),
                                ),
                                Text(
                                  'To: ${_shortenId(msg.nextHopPeerId)} · Attempts: ${msg.attemptCount}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: priorityColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _priorityLabel(msg.message.priority.index),
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: priorityColor),
                            ),
                          ),
                        ],
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppTheme.accentBorderCard(radius: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    appState.initials,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appState.displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      Text(
                        'ID: ${_shortenId(appState.meshRouter.localPeerId)}',
                        style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Connected peers section
          Text(
            'Connected Peers (${_connectedPeerIds.length})',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          if (_connectedPeerIds.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.glassCard(radius: 12),
              child: Row(
                children: [
                  Icon(Icons.signal_wifi_off_rounded, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No connected peers', style: GoogleFonts.inter(color: AppTheme.textPrimary, fontWeight: FontWeight.w500)),
                        Text('Ensure Bluetooth and WiFi are enabled', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_connectedPeerIds.length, (i) {
              final peerId = _connectedPeerIds[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.online.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.online.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.online.withValues(alpha: 0.15),
                        child: const Icon(Icons.link_rounded, color: AppTheme.online, size: 16),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_shortenId(peerId), style: GoogleFonts.firaCode(fontSize: 12, color: AppTheme.textPrimary)),
                            Text('Active connection', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.online)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

          const SizedBox(height: 20),

          if (_routingStats != null) ...[
            Text(
              'Delivery Stats',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.glassCard(radius: 12),
              child: Wrap(
                alignment: WrapAlignment.spaceAround,
                runSpacing: 10,
                spacing: 10,
                children: [
                  _statChip('Sent', _routingStats!.messagesSent, AppTheme.accent),
                  _statChip('Delivered', _routingStats!.messagesDelivered,
                      AppTheme.online),
                  _statChip('Failed', _routingStats!.messagesFailed,
                      AppTheme.danger),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(_routingStats!.deliverySuccessRate * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.warning,
                        ),
                      ),
                      Text(
                        'Success',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // All known peers
          Text(
            'All Known Peers (${appState.peers.length})',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          ...appState.peers.map((peer) {
            final isConnected = _connectedPeerIds.contains(peer.id);
            final lastSeenAgo = DateTime.now().millisecondsSinceEpoch - peer.lastSeen;
            final minutes = (lastSeenAgo / 60000).floor();

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: AppTheme.glassCard(radius: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: (isConnected ? AppTheme.online : AppTheme.textSecondary).withValues(alpha: 0.15),
                      child: Text(
                        peer.displayName.isNotEmpty ? peer.displayName[0].toUpperCase() : '?',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isConnected ? AppTheme.online : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(peer.displayName, style: GoogleFonts.inter(fontWeight: FontWeight.w500, color: AppTheme.textPrimary, fontSize: 13)),
                          Text(
                            '${_shortenId(peer.id)} · ${peer.hasApp ? "PeerChat" : "BT only"} · ${minutes}m ago',
                            style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isConnected ? Icons.link_rounded : Icons.link_off_rounded,
                      color: isConnected ? AppTheme.online : AppTheme.textSecondary.withValues(alpha: 0.5),
                      size: 18,
                    ),
                  ],
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
        Text(
          '$count',
          style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: color),
        ),
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  String _shortenId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}…${id.substring(id.length - 6)}';
  }

  Color _priorityColor(int priority) {
    switch (priority) {
      case 2: return AppTheme.danger;
      case 1: return AppTheme.warning;
      default: return AppTheme.textSecondary;
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
