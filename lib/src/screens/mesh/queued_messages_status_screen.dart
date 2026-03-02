import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/mesh_router_service.dart';
import '../../models/queued_message.dart';
import '../../config/identity_ui_config.dart';
import '../../theme.dart';
import '../../utils/name_generator.dart';

class QueuedMessagesStatusScreen extends StatefulWidget {
  final QueueOrigin origin;
  final String title;

  const QueuedMessagesStatusScreen.local({super.key})
      : origin = QueueOrigin.local,
        title = 'Local Queue';

  const QueuedMessagesStatusScreen.mesh({super.key})
      : origin = QueueOrigin.mesh,
        title = 'Mesh Queue';

  @override
  State<QueuedMessagesStatusScreen> createState() =>
      _QueuedMessagesStatusScreenState();
}

class _QueuedMessagesStatusScreenState
    extends State<QueuedMessagesStatusScreen> {
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
    if (value.length <= IdPreviewConfig.fullDisplayThreshold) return value;
    return '${value.substring(0, IdPreviewConfig.leadingChars)}…${value.substring(value.length - IdPreviewConfig.statusTrailingChars)}';
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

  Future<void> _deletePeerSet(String peerId, QueueOrigin origin) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final removed = await appState.meshRouter.removeQueuedMessagesForPeer(
      peerId,
      origin: origin,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $removed queued message(s)')),
    );
    await _load();
  }

  Future<void> _promoteMessageToMesh(String messageId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final moved = await appState.meshRouter.promoteQueuedMessageToMesh(messageId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          moved > 0
              ? 'Message moved to mesh queue'
              : 'Message was not in local queue',
        ),
      ),
    );
    await _load();
  }

  Future<void> _promotePeerSetToMesh(String peerId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final moved =
        await appState.meshRouter.promoteQueuedMessagesForPeerToMesh(peerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved $moved message(s) to mesh queue')),
    );
    await _load();
  }

  Map<String, List<QueuedMessageDetail>> _groupByRecipient(
    List<QueuedMessageDetail> items,
  ) {
    final grouped = <String, List<QueuedMessageDetail>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.recipientPeerId, () => []).add(item);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => a.queuedTimestamp.compareTo(b.queuedTimestamp));
    }
    return grouped;
  }

  List<String> _sortedPeerIds(
    AppState appState,
    Map<String, List<QueuedMessageDetail>> grouped,
  ) {
    final peerIds = grouped.keys.toList();
    peerIds.sort((a, b) {
      final nameA = _peerName(appState, a).toLowerCase();
      final nameB = _peerName(appState, b).toLowerCase();
      return nameA.compareTo(nameB);
    });
    return peerIds;
  }

  Widget _buildPeerQueueCard(
    AppState appState,
    String peerId,
    List<QueuedMessageDetail> messages,
    QueueOrigin origin,
  ) {
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (origin == QueueOrigin.local)
              IconButton(
                tooltip: 'Move all for this peer to mesh queue',
                onPressed: () => _promotePeerSetToMesh(peerId),
                icon: const Icon(
                  Icons.alt_route_rounded,
                  color: AppTheme.warning,
                ),
              ),
            IconButton(
              tooltip: 'Delete all for this peer in this queue',
              onPressed: () => _deletePeerSet(peerId, origin),
              icon: const Icon(
                Icons.delete_sweep_rounded,
                color: AppTheme.danger,
              ),
            ),
          ],
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (origin == QueueOrigin.local)
                        IconButton(
                          tooltip: 'Move to mesh queue',
                          onPressed: () => _promoteMessageToMesh(message.messageId),
                          icon: const Icon(
                            Icons.alt_route_rounded,
                            color: AppTheme.warning,
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
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueList(
    AppState appState, {
    required QueueOrigin origin,
    required List<QueuedMessageDetail> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final grouped = _groupByRecipient(items);
    final peerIds = _sortedPeerIds(appState, grouped);

    return Column(
      children: [
        for (final peerId in peerIds)
          _buildPeerQueueCard(appState, peerId, grouped[peerId]!, origin),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final filteredItems =
        _items.where((item) => item.origin == widget.origin).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
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
          : filteredItems.isEmpty
              ? Center(
                  child: Text(
                    '${widget.title} is empty',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    _buildQueueList(
                      appState,
                      origin: widget.origin,
                      items: filteredItems,
                    ),
                  ],
                ),
    );
  }
}

