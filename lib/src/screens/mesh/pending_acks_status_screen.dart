import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/mesh_router_service.dart';
import '../../theme.dart';
import '../../utils/name_generator.dart';

class PendingAcksStatusScreen extends StatefulWidget {
  const PendingAcksStatusScreen({super.key});

  @override
  State<PendingAcksStatusScreen> createState() => _PendingAcksStatusScreenState();
}

class _PendingAcksStatusScreenState extends State<PendingAcksStatusScreen> {
  bool _isLoading = true;
  List<PendingAckDetail> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final items = await appState.meshRouter.getPendingAckDetails();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  String _peerName(AppState appState, String peerId) {
    for (final peer in appState.peers) {
      if (peer.id == peerId) {
        if (peer.id.length > 40) return NameGenerator.generateShortName(peerId);
        return peer.displayName;
      }
    }
    return NameGenerator.generateShortName(peerId);
  }

  String _timeLabel(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _short(String value) {
    if (value.length <= 12) return value;
    return '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
  }

  Future<void> _queueOne(PendingAckDetail detail) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final ok = await appState.meshRouter.queuePendingAckForMessage(detail.messageId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Queued for resend: ${_short(detail.messageId)}'
            : 'Unable to queue ${_short(detail.messageId)}'),
      ),
    );
    await _load();
  }

  Future<void> _queuePeerSet(String peerId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final queued = await appState.meshRouter.queuePendingAcksForPeer(peerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Queued $queued pending ACK message(s) in original order'),
      ),
    );
    await _load();
  }

  Future<void> _clearAllPendingAcks() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final removed = await appState.meshRouter.clearPendingAcks();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cleared $removed pending ACK record(s)'),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final grouped = <String, List<PendingAckDetail>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.recipientPeerId, () => []).add(item);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.orderTimestamp.compareTo(b.orderTimestamp));
    }
    final peerIds = grouped.keys.toList()
      ..sort((a, b) {
        final nameA = _peerName(appState, a).toLowerCase();
        final nameB = _peerName(appState, b).toLowerCase();
        return nameA.compareTo(nameB);
      });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pending ACKs',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: 'Clear all pending ACKs',
            onPressed: _clearAllPendingAcks,
          ),
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
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'No pending ACKs',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'Queue resend preserves original message order using stored timestamps.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    for (final peerId in peerIds)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          title: Text(
                            _peerName(appState, peerId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            '${grouped[peerId]!.length} pending ACK(s)',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Queue resend all for this peer',
                            onPressed: () => _queuePeerSet(peerId),
                            icon: const Icon(
                              Icons.playlist_add_check_circle_rounded,
                              color: AppTheme.primary,
                            ),
                          ),
                          children: [
                            for (final item in grouped[peerId]!)
                              Container(
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgSurface,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: AppTheme.accent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.contentPreview ??
                                                '[Message body unavailable]',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Sent ${_timeLabel(item.sentTimestamp)} • ${_short(item.messageId)}',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Queue resend',
                                      onPressed: () => _queueOne(item),
                                      icon: const Icon(
                                        Icons.replay_rounded,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
