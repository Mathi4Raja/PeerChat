import 'dart:async';
import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../models/communication_mode.dart';
import '../models/mesh_message.dart';
import '../config/limits_config.dart';
import '../config/timer_config.dart';
import '../services/menu_settings_service.dart';
import '../services/mesh_router_service.dart';
import '../services/notification_sound_service.dart';
import '../theme.dart';
import '../utils/name_generator.dart';

class EmergencyBroadcastScreen extends StatefulWidget {
  const EmergencyBroadcastScreen({super.key});

  @override
  State<EmergencyBroadcastScreen> createState() =>
      _EmergencyBroadcastScreenState();
}

class _EmergencyBroadcastScreenState extends State<EmergencyBroadcastScreen> {
  static const int _messageLineChunk = 20;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final NotificationSoundService _notificationSoundService =
      NotificationSoundService();
  StreamSubscription<Map<String, Object?>>? _broadcastSubscription;
  final Map<String, Timer> _retryCountdownTimers = {};
  final Map<String, Timer> _failedVisibilityTimers = {};
  final Map<String, int> _messageLineLimits = {};
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightResetTimer;
  Map<String, Object?>? _replyingTo;

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
    for (final timer in _retryCountdownTimers.values) {
      timer.cancel();
    }
    for (final timer in _failedVisibilityTimers.values) {
      timer.cancel();
    }
    _highlightResetTimer?.cancel();
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
    final deleted = event['deleted'] as bool? ?? false;
    if (id.isNotEmpty && deleted) {
      _retryCountdownTimers.remove(id)?.cancel();
      _failedVisibilityTimers.remove(id)?.cancel();
      setState(() {
        final replyingId = (_replyingTo?['id'] as String?) ?? '';
        if (replyingId == id) {
          _replyingTo = null;
        }
        _messages = _messages
            .where((row) => (row['id'] as String?) != id)
            .toList(growable: false);
      });
      return;
    }

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
      Map<String, Object?>? previous;
      for (final row in updated) {
        if ((row['id'] as String?) == id) {
          previous = row;
          break;
        }
      }
      updated.removeWhere((row) => (row['id'] as String?) == id);
      final merged = <String, Object?>{
        'id': id,
        'sender_id': senderId,
        'content': content,
        'timestamp': timestamp,
        'signature': event['signature'],
      };
      if (previous != null) {
        for (final entry in previous.entries) {
          if (entry.key.startsWith('local_')) {
            merged[entry.key] = entry.value;
          }
        }
      }

      final localPeerId = Provider.of<AppState>(context, listen: false).publicKey ?? '';
      if (localPeerId.isNotEmpty && senderId == localPeerId) {
        merged['local_status'] = 'delivered';
        merged.remove('local_retry_deadline_ms');
        merged.remove('local_retry_remaining_s');
        _retryCountdownTimers.remove(id)?.cancel();
      }
      updated.insert(0, merged);
      if (updated.length > BroadcastLimits.screenHistoryLimit) {
        updated.removeRange(BroadcastLimits.screenHistoryLimit, updated.length);
      }
      _messages = updated;
      _loading = false;
    });
  }

  String _generateEmergencyMessageId(String localPeerId) {
    final prefix = localPeerId.length >= MessageLimits.generatedIdSenderPrefixLength
        ? localPeerId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
        : localPeerId;
    final compactUuid = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    return '${prefix}_$compactUuid';
  }

  void _insertLocalMessage({
    required String id,
    required String senderId,
    required String content,
    required int timestamp,
    required String status,
    String? failureReason,
    int? retryDeadlineMs,
  }) {
    setState(() {
      final updated = List<Map<String, Object?>>.from(_messages);
      updated.removeWhere((row) => (row['id'] as String?) == id);
      final row = <String, Object?>{
        'id': id,
        'sender_id': senderId,
        'content': content,
        'timestamp': timestamp,
        'signature': null,
        'local_status': status,
      };
      if (retryDeadlineMs != null) {
        row['local_retry_deadline_ms'] = retryDeadlineMs;
        final remainingSec = ((retryDeadlineMs - DateTime.now().millisecondsSinceEpoch + 999) ~/ 1000);
        row['local_retry_remaining_s'] = remainingSec > 0 ? remainingSec : 0;
      }
      if (failureReason != null && failureReason.isNotEmpty) {
        row['local_failure_reason'] = failureReason;
      }
      updated.insert(0, row);
      if (updated.length > BroadcastLimits.screenHistoryLimit) {
        updated.removeRange(BroadcastLimits.screenHistoryLimit, updated.length);
      }
      _messages = updated;
    });
  }

  void _setLocalStatus(
    String id,
    String status, {
    String? failureReason,
  }) {
    if (!mounted) return;
    setState(() {
      final updated = List<Map<String, Object?>>.from(_messages);
      for (var i = 0; i < updated.length; i++) {
        final row = updated[i];
        if ((row['id'] as String?) != id) continue;
        final next = Map<String, Object?>.from(row);
        next['local_status'] = status;
        if (status != 'queued') {
          next.remove('local_retry_deadline_ms');
          next.remove('local_retry_remaining_s');
        }
        if (failureReason != null) {
          next['local_failure_reason'] = failureReason;
        }
        updated[i] = next;
        _messages = updated;
        return;
      }
    });
  }

  void _startRetryCountdown(String id, int deadlineMs) {
    _retryCountdownTimers.remove(id)?.cancel();
    _retryCountdownTimers[id] = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remainingMs = deadlineMs - DateTime.now().millisecondsSinceEpoch;
      final remainingSec = remainingMs <= 0 ? 0 : ((remainingMs + 999) ~/ 1000);
      setState(() {
        final updated = List<Map<String, Object?>>.from(_messages);
        for (var i = 0; i < updated.length; i++) {
          final row = updated[i];
          if ((row['id'] as String?) != id) continue;
          final status = (row['local_status'] as String?) ?? '';
          if (status != 'queued') {
            timer.cancel();
            _retryCountdownTimers.remove(id);
            return;
          }
          final next = Map<String, Object?>.from(row);
          next['local_retry_remaining_s'] = remainingSec;
          updated[i] = next;
          _messages = updated;
          if (remainingSec <= 0) {
            timer.cancel();
            _retryCountdownTimers.remove(id);
          }
          return;
        }
        timer.cancel();
        _retryCountdownTimers.remove(id);
      });
    });
  }

  Future<void> _purgeFailedMessageHard(String id) async {
    _retryCountdownTimers.remove(id)?.cancel();
    _failedVisibilityTimers.remove(id)?.cancel();

    if (mounted) {
      setState(() {
        final replyingId = (_replyingTo?['id'] as String?) ?? '';
        if (replyingId == id) {
          _replyingTo = null;
        }
        _messages = _messages
            .where((row) => (row['id'] as String?) != id)
            .toList(growable: false);
      });
    }

    // Ensure failed items leave no persisted trace either.
    final appState = Provider.of<AppState>(context, listen: false);
    await appState.db.deleteBroadcastMessage(id);
  }

  void _scheduleFailedDelete(String id) {
    _failedVisibilityTimers.remove(id)?.cancel();
    _failedVisibilityTimers[id] = Timer(const Duration(seconds: 3), () {
      unawaited(_purgeFailedMessageHard(id));
    });
  }

  void _startReply({
    required String messageId,
    required String senderLabel,
    required String content,
  }) {
    setState(() {
      _replyingTo = {
        'id': messageId,
        'sender': senderLabel,
        'content': content,
      };
    });
  }

  void _cancelReply() {
    if (_replyingTo == null) return;
    setState(() {
      _replyingTo = null;
    });
  }

  String _replySnippet(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 60) return compact;
    return '${compact.substring(0, 60)}...';
  }

  int _lineLimitForMessage(String messageId) {
    return _messageLineLimits[messageId] ?? _messageLineChunk;
  }

  void _expandMessageLines(String messageId) {
    setState(() {
      _messageLineLimits[messageId] =
          _lineLimitForMessage(messageId) + _messageLineChunk;
    });
  }

  void _collapseExpandedMessages() {
    if (_messageLineLimits.isEmpty) return;
    setState(() {
      _messageLineLimits.clear();
    });
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  String _senderLabelForRow(Map<String, Object?> row, String localPeerId) {
    final senderId = (row['sender_id'] as String?) ?? '';
    final isMe = localPeerId.isNotEmpty && senderId == localPeerId;
    if (isMe) return 'You';
    if (senderId.isEmpty) return 'Unknown';
    return NameGenerator.generateShortName(senderId);
  }

  String _baseContentForRow(Map<String, Object?> row) {
    final content = (row['content'] as String?) ?? '';
    return _splitReplyContent(content).body;
  }

  Future<void> _jumpToReplyTarget(String replyHeader) async {
    if (!mounted) return;
    final colonIndex = replyHeader.indexOf(':');
    if (colonIndex <= 0) return;

    final targetSender = replyHeader.substring(0, colonIndex).trim();
    final targetSnippet = replyHeader.substring(colonIndex + 1).trim();
    if (targetSender.isEmpty || targetSnippet.isEmpty) return;

    final localPeerId =
        Provider.of<AppState>(context, listen: false).publicKey ?? '';
    String? targetMessageId;
    for (final row in _messages) {
      final senderLabel = _senderLabelForRow(row, localPeerId);
      if (senderLabel != targetSender) continue;
      final baseContent = _baseContentForRow(row).trim();
      if (baseContent.isEmpty) continue;
      if (baseContent.startsWith(targetSnippet) ||
          targetSnippet.startsWith(baseContent) ||
          baseContent.contains(targetSnippet)) {
        targetMessageId = (row['id'] as String?) ?? '';
        if (targetMessageId.isNotEmpty) break;
      }
    }

    if (targetMessageId == null || targetMessageId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original replied message not found')),
      );
      return;
    }

    final targetKey = _messageKeyFor(targetMessageId);
    final targetContext = targetKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: UiTimerConfig.chatAutoScrollAnimation,
        curve: Curves.easeOut,
        alignment: 0.25,
      );
    }

    if (!mounted) return;
    setState(() {
      _highlightedMessageId = targetMessageId;
    });
    _highlightResetTimer?.cancel();
    _highlightResetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        if (_highlightedMessageId == targetMessageId) {
          _highlightedMessageId = null;
        }
      });
    });
  }

  String _composeOutgoingContent(String content) {
    final reply = _replyingTo;
    if (reply == null) return content;
    final sender = (reply['sender'] as String?) ?? 'Unknown';
    final quoted = _replySnippet((reply['content'] as String?) ?? '');
    return '↪ $sender: $quoted\n$content';
  }

  Future<void> _sendBroadcast() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final soundEnabled =
        Provider.of<MenuSettingsController>(context, listen: false)
            .notifications
            .sound;
    final rawContent = _inputController.text.trim();
    final content = _composeOutgoingContent(rawContent);
    final timing = appState.emergencyBroadcastService.timing;
    final maxPerMinute =
        appState.emergencyBroadcastService.maxBroadcastsPerMinute;
    if (rawContent.isEmpty || _sending) return;

    final localPeerId = appState.publicKey ?? '';
    final messageId = _generateEmergencyMessageId(
      localPeerId.isEmpty ? 'localpeer' : localPeerId,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final deadlineMs = now + timing.queueWindow.inMilliseconds;

    _insertLocalMessage(
      id: messageId,
      senderId: localPeerId,
      content: content,
      timestamp: now,
      status: 'queued',
      retryDeadlineMs: deadlineMs,
    );
    _startRetryCountdown(messageId, deadlineMs);

    _inputController.clear();
    _cancelReply();

    setState(() => _sending = true);

    if (!appState.emergencyBroadcastService.canLocalSenderBroadcast()) {
      _setLocalStatus(
        messageId,
        'failed',
        failureReason: 'Rate limit reached ($maxPerMinute/min)',
      );
      _scheduleFailedDelete(messageId);
      _retryCountdownTimers.remove(messageId)?.cancel();
      if (mounted) {
        setState(() => _sending = false);
      }
      return;
    }

    final result = await appState.meshRouter.sendMessage(
      recipientPeerId: broadcastEmergencyDestination,
      content: content,
      priority: MessagePriority.high,
      messageId: messageId,
    );
    if (!mounted) return;
    setState(() => _sending = false);

    if (result == SendResult.routed) {
      _setLocalStatus(messageId, 'delivered');
      _retryCountdownTimers.remove(messageId)?.cancel();
      if (soundEnabled) {
        unawaited(_notificationSoundService.playSentTick());
      }
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: UiTimerConfig.emergencyAutoScrollAnimation,
          curve: Curves.easeOut,
        );
      }
    } else {
      _setLocalStatus(
        messageId,
        'failed',
        failureReason:
            'No nearby relay responded in ${timing.queueWindow.inSeconds}s',
      );
      _retryCountdownTimers.remove(messageId)?.cancel();
      _scheduleFailedDelete(messageId);
    }
  }

  ({String? replyHeader, String body}) _splitReplyContent(String content) {
    final newlineIndex = content.indexOf('\n');
    if (newlineIndex > 0 && content.startsWith('↪ ')) {
      final header = content.substring(2, newlineIndex).trim();
      final body = content.substring(newlineIndex + 1).trim();
      if (header.isNotEmpty && body.isNotEmpty) {
        return (replyHeader: header, body: body);
      }
    }
    return (replyHeader: null, body: content);
  }

  Widget _buildStatusIndicator({
    required bool isMe,
    required Map<String, Object?> row,
    required DateTime time,
  }) {
    final style = GoogleFonts.inter(
      fontSize: 11,
      color: AppTheme.textSecondary,
    );

    if (!isMe) {
      return Text(
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        style: style,
      );
    }

    final localStatus = (row['local_status'] as String?) ?? 'delivered';
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    if (localStatus == 'queued') {
      final remaining = (row['local_retry_remaining_s'] as int?) ?? 0;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.schedule_rounded, size: 13, color: AppTheme.warning),
          const SizedBox(width: 2),
          Text('${remaining}s', style: style),
        ],
      );
    }

    if (localStatus == 'failed') {
      return const Icon(
        Icons.warning_amber_rounded,
        size: 14,
        color: AppTheme.warning,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_rounded, size: 14, color: AppTheme.online),
        const SizedBox(width: 2),
        Text(timeText, style: style),
      ],
    );
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _collapseExpandedMessages,
        child: Column(
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

                              final localStatus =
                                  (row['local_status'] as String?) ?? '';
                              final failureReason =
                                  (row['local_failure_reason'] as String?) ?? '';
                              final parsed = _splitReplyContent(content);
                              final replyHeader = parsed.replyHeader;
                              final bodyText = parsed.body;
                              final messageId = (row['id'] as String?) ?? '';
                              final isHighlighted =
                                  messageId.isNotEmpty &&
                                  _highlightedMessageId == messageId;
                              final lineLimit = messageId.isEmpty
                                  ? _messageLineChunk
                                  : _lineLimitForMessage(messageId);

                              return Dismissible(
                                key: ValueKey(
                                  'broadcast_${row['id'] ?? 'idx'}_$index',
                                ),
                                direction: DismissDirection.startToEnd,
                                confirmDismiss: (_) async {
                                  _startReply(
                                    messageId: (row['id'] as String?) ?? '',
                                    senderLabel: senderLabel,
                                    content: bodyText,
                                  );
                                  return false;
                                },
                                background: Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14),
                                  alignment: Alignment.centerLeft,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.reply_rounded,
                                        color: AppTheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Reply',
                                        style: GoogleFonts.inter(
                                          color: AppTheme.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                child: Align(
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
                                      key: messageId.isEmpty
                                          ? null
                                          : _messageKeyFor(messageId),
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? AppTheme.primary
                                                .withValues(alpha: 0.14)
                                            : AppTheme.danger
                                                .withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isHighlighted
                                              ? AppTheme.warning
                                                  .withValues(alpha: 0.90)
                                              : localStatus == 'failed'
                                                  ? AppTheme.warning
                                                      .withValues(alpha: 0.45)
                                                  : isMe
                                                      ? AppTheme.primary
                                                          .withValues(alpha: 0.32)
                                                      : AppTheme.danger
                                                          .withValues(alpha: 0.25),
                                          width: isHighlighted ? 1.5 : 1.0,
                                        ),
                                        boxShadow: isHighlighted
                                            ? [
                                                BoxShadow(
                                                  color: AppTheme.warning
                                                      .withValues(alpha: 0.30),
                                                  blurRadius: 10,
                                                  spreadRadius: 0.5,
                                                ),
                                              ]
                                            : null,
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
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _buildStatusIndicator(
                                                isMe: isMe,
                                                row: row,
                                                time: time,
                                              ),
                                            ],
                                          ),
                                          if (replyHeader != null) ...[
                                            const SizedBox(height: 6),
                                            GestureDetector(
                                              onTap: () =>
                                                  _jumpToReplyTarget(replyHeader),
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.bgSurface
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: AppTheme.primary
                                                        .withValues(alpha: 0.28),
                                                  ),
                                                ),
                                                child: Text(
                                                  replyHeader,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color:
                                                        AppTheme.textSecondary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          LayoutBuilder(
                                            builder: (context, constraints) {
                                              final textStyle = GoogleFonts.inter(
                                                fontSize: 14,
                                                color: AppTheme.textPrimary,
                                              );
                                              final painter = TextPainter(
                                                text: TextSpan(
                                                  text: bodyText,
                                                  style: textStyle,
                                                ),
                                                maxLines: lineLimit,
                                                textDirection: TextDirection.ltr,
                                              )..layout(
                                                  maxWidth: constraints.maxWidth);
                                              final hasMore =
                                                  painter.didExceedMaxLines;

                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    bodyText,
                                                    maxLines: lineLimit,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: textStyle,
                                                  ),
                                                  if (hasMore &&
                                                      messageId.isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    GestureDetector(
                                                      onTap: () =>
                                                          _expandMessageLines(
                                                              messageId),
                                                      child: Text(
                                                        'Read more...',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              AppTheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                          if (localStatus == 'failed' &&
                                              failureReason.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              failureReason,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppTheme.warning,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_replyingTo != null) ...[
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.reply_rounded,
                            size: 14,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Replying to ${(_replyingTo!['sender'] as String?) ?? 'Unknown'}: ${_replySnippet((_replyingTo!['content'] as String?) ?? '')}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _cancelReply,
                            icon: const Icon(Icons.close_rounded, size: 16),
                            splashRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                  Row(
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
                ],
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
