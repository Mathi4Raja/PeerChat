import 'dart:async';
import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/communication_mode.dart';
import '../models/mesh_message.dart';
import '../config/limits_config.dart';
import '../config/timer_config.dart';
import '../services/mesh_router_service.dart';
import '../theme.dart';
import '../utils/name_generator.dart';

class EmergencyBroadcastScreen extends StatefulWidget {
  const EmergencyBroadcastScreen({super.key});

  @override
  State<EmergencyBroadcastScreen> createState() =>
      _EmergencyBroadcastScreenState();
}

class _EmergencyBroadcastScreenState extends State<EmergencyBroadcastScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, Object?>>? _broadcastSubscription;

  List<Map<String, Object?>> _messages = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    final appState = Provider.of<AppState>(context, listen: false);
    _broadcastSubscription =
        appState.emergencyBroadcastService.onBroadcastMessage.listen(
      _upsertIncomingBroadcast,
    );
  }

  @override
  void dispose() {
    _broadcastSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final rows = await appState.db
        .getBroadcastMessages(limit: BroadcastLimits.screenHistoryLimit);
    if (!mounted) return;
    setState(() {
      _messages = rows;
      _loading = false;
    });
  }

  void _upsertIncomingBroadcast(Map<String, Object?> event) {
    if (!mounted) return;
    final id = (event['id'] as String?) ?? '';
    final senderId = (event['sender_id'] as String?) ?? '';
    final content = (event['content'] as String?) ?? '';
    final timestamp = event['timestamp'] as int?;

    if (id.isEmpty ||
        senderId.isEmpty ||
        content.isEmpty ||
        timestamp == null) {
      return;
    }

    setState(() {
      final updated = List<Map<String, Object?>>.from(_messages);
      updated.removeWhere((row) => (row['id'] as String?) == id);
      updated.insert(0, {
        'id': id,
        'sender_id': senderId,
        'content': content,
        'timestamp': timestamp,
        'signature': event['signature'],
      });
      if (updated.length > BroadcastLimits.screenHistoryLimit) {
        updated.removeRange(BroadcastLimits.screenHistoryLimit, updated.length);
      }
      _messages = updated;
      _loading = false;
    });
  }

  Future<void> _sendBroadcast() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final content = _inputController.text.trim();
    final maxPerMinute =
        appState.emergencyBroadcastService.maxBroadcastsPerMinute;
    if (content.isEmpty || _sending) return;

    if (!appState.emergencyBroadcastService.canLocalSenderBroadcast()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rate limit reached: max $maxPerMinute emergency messages per minute.',
          ),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    final result = await appState.meshRouter.sendMessage(
      recipientPeerId: broadcastEmergencyDestination,
      content: content,
      priority: MessagePriority.high,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result == SendResult.routed || result == SendResult.direct) {
      _inputController.clear();
      await _loadMessages();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: UiTimerConfig.emergencyAutoScrollAnimation,
          curve: Curves.easeOut,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('failed to save locally.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final maxPerMinute =
        appState.emergencyBroadcastService.maxBroadcastsPerMinute;
    final remainingQuota = appState.emergencyBroadcastService
        .remainingQuotaForSender(appState.publicKey ?? '');
    final connectedPeerCount = appState.meshRouter.getConnectedPeerIds().length;
    final onlineInChannel = connectedPeerCount + 1; // include local user
    final onlineLabel = onlineInChannel > UiLimits.onlineCountDisplayCap
        ? '${UiLimits.onlineCountDisplayCap}+'
        : '$onlineInChannel';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Emergency',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _loadMessages,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppTheme.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Public emergency channel. Signed but not encrypted.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$remainingQuota/$maxPerMinute',
                      style: GoogleFonts.inter(
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Online: $onlineLabel',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.warning),
                  )
                : RefreshIndicator(
                    onRefresh: _loadMessages,
                    child: _messages.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.62,
                                child: Center(
                                  child: Text(
                                    'No emergency broadcasts yet',
                                    style: GoogleFonts.inter(
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final row = _messages[index];
                              final senderId =
                                  (row['sender_id'] as String?) ?? '';
                              final content = (row['content'] as String?) ?? '';
                              final timestamp = (row['timestamp'] as int?) ?? 0;
                              final time = DateTime.fromMillisecondsSinceEpoch(
                                  timestamp);
                              final localPeerId = appState.publicKey ?? '';
                              final isMe = localPeerId.isNotEmpty &&
                                  senderId == localPeerId;
                              final senderLabel = isMe
                                  ? 'You'
                                  : (senderId.isEmpty
                                      ? 'Unknown'
                                      : NameGenerator.generateShortName(
                                          senderId,
                                        ));

                              return Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.88,
                                  ),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isMe
                                          ? AppTheme.primary
                                              .withValues(alpha: 0.14)
                                          : AppTheme.danger
                                              .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isMe
                                            ? AppTheme.primary
                                                .withValues(alpha: 0.32)
                                            : AppTheme.danger
                                                .withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              isMe
                                                  ? Icons.person_rounded
                                                  : Icons.verified_rounded,
                                              size: 14,
                                              color: isMe
                                                  ? AppTheme.primary
                                                  : AppTheme.online,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                senderLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          content,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Emergency update...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sending ? null : _sendBroadcast,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.campaign_rounded, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

