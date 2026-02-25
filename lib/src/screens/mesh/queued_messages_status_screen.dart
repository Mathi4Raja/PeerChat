import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/mesh_router_service.dart';
import '../../theme.dart';
import '../../utils/name_generator.dart';

class QueuedMessagesStatusScreen extends StatefulWidget {
  const QueuedMessagesStatusScreen({super.key});

  @override
  State<QueuedMessagesStatusScreen> createState() =>
      _QueuedMessagesStatusScreenState();
}

class _QueuedMessagesStatusScreenState extends State<QueuedMessagesStatusScreen> {
  bool _isLoading = true;
  List<QueuedMessageDetail> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final items = await appState.meshRouter.getQueuedMessageDetails();
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

  Color _priorityColor(int index) {
    switch (index) {
      case 0:
        return AppTheme.danger;
      case 1:
        return AppTheme.warning;
      default:
        return AppTheme.textSecondary;
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.meshRouter.removeQueuedMessage(messageId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued message removed')),
    );
    await _load();
  }

  Future<void> _deletePeerSet(String peerId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final removed = await appState.meshRouter.removeQueuedMessagesForPeer(peerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $removed queued message(s)')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final grouped = <String, List<QueuedMessageDetail>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.recipientPeerId, () => []).add(item);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.queuedTimestamp.compareTo(b.queuedTimestamp));
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
          'Queued Messages',
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
          : _items.isEmpty
              ? Center(
                  child: Text(
                    'Queue is empty',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: peerIds.length,
                  itemBuilder: (context, index) {
                    final peerId = peerIds[index];
                    final messages = grouped[peerId]!;
                    return Container(
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
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                          '${messages.length} message(s) • ordered by queue time',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Delete all for this peer',
                          onPressed: () => _deletePeerSet(peerId),
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            color: AppTheme.danger,
                          ),
                        ),
                        leading: Text(
                          '${messages.length}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.warning,
                          ),
                        ),
                        children: [
                          for (final message in messages)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppTheme.bgSurface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _priorityColor(message.priority.index),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          message.contentPreview ?? '[Encrypted message]',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Queued ${_timeLabel(message.queuedTimestamp)} • attempt ${message.attemptCount + 1} • ${_short(message.messageId)}',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    onPressed: () => _deleteMessage(message.messageId),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppTheme.danger,
                                    ),
                                  ),
                                ],
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
