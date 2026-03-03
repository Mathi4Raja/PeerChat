import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../models/route.dart' as mesh_route;
import '../../config/identity_ui_config.dart';
import '../../theme.dart';
import '../../utils/name_generator.dart';

class RoutesStatusScreen extends StatefulWidget {
  const RoutesStatusScreen({super.key});

  @override
  State<RoutesStatusScreen> createState() => _RoutesStatusScreenState();
}

class _RoutesStatusScreenState extends State<RoutesStatusScreen> {
  bool _isLoading = true;
  List<mesh_route.Route> _routes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final routes = await appState.meshRouter.getAllRoutesForStatus();
    routes.sort(
      (a, b) => b.lastUpdatedTimestamp.compareTo(a.lastUpdatedTimestamp),
    );
    if (!mounted) return;
    setState(() {
      _routes = routes;
      _isLoading = false;
    });
  }

  String _peerName(AppState appState, String peerId) {
    if (peerId == appState.publicKey) return 'You';
    for (final peer in appState.peers) {
      if (peer.id == peerId) {
        if (peer.id.length > 40) return NameGenerator.generateShortName(peerId);
        return peer.displayName;
      }
    }
    return NameGenerator.generateShortName(peerId);
  }

  String _timeAgo(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = now - timestamp;
    if (diff < TimeFormatConfig.minuteMs) {
      return '${(diff / TimeFormatConfig.secondMs).round()}s ago';
    }
    if (diff < TimeFormatConfig.hourMs) {
      return '${(diff / TimeFormatConfig.minuteMs).round()}m ago';
    }
    if (diff < TimeFormatConfig.dayMs) {
      return '${(diff / TimeFormatConfig.hourMs).round()}h ago';
    }
    return '${(diff / TimeFormatConfig.dayMs).round()}d ago';
  }

  String _reliability(mesh_route.Route route) {
    final total = route.successCount + route.failureCount;
    if (total == 0) return 'No history';
    final pct = ((route.successCount / total) * 100).round();
    return '$pct% success';
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Routes',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : _routes.isEmpty
              ? Center(
                  child: Text(
                    'No routes available',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final route = _routes[index];
                    final destination =
                        _peerName(appState, route.destinationPeerId);
                    final nextHop = _peerName(appState, route.nextHopPeerId);
                    final isSingleHop =
                        route.destinationPeerId == route.nextHopPeerId;
                    final statusColor =
                        route.isStale ? AppTheme.warning : AppTheme.online;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSingleHop
                                    ? Icons.near_me_rounded
                                    : Icons.alt_route_rounded,
                                color: statusColor,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  destination,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                              Text(
                                route.isStale ? 'STALE' : 'ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isSingleHop
                                ? 'Single-hop route'
                                : 'Via $nextHop • ${route.hopCount} hops',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_reliability(route)} • Last used ${_timeAgo(route.lastUsedTimestamp)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

