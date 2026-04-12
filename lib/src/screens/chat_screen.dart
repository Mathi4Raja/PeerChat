import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../services/mesh_router_service.dart';
import '../services/menu_settings_service.dart';
import '../services/notification_sound_service.dart';
import '../models/mesh_message.dart';
import '../models/chat_payload.dart';
import '../models/chat_message.dart';
import '../models/peer.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import '../theme.dart';
import '../utils/name_generator.dart';
import 'first_sign_in_screen.dart';
import 'web_share_asset_picker.dart';
import 'direct_transfer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String? preselectedPeerId;

  const ChatScreen({super.key, this.preselectedPeerId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _messageLineChunk = 20;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final NotificationSoundService _notificationSoundService =
      NotificationSoundService();
  String? _selectedPeerId;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  StreamSubscription<ChatMessage>? _incomingMessageSubscription;
  StreamSubscription<String>? _statusChangeSubscription;
  ChatMessage? _replyingTo;
  final Map<String, int> _messageLineLimits = {};
  final Map<String, GlobalKey> _messageKeys = {};
  String? _highlightedMessageId;
  Timer? _highlightResetTimer;

  @override
  void initState() {
    super.initState();
    _selectedPeerId = widget.preselectedPeerId;
    if (_selectedPeerId != null) {
      _loadMessages();
    }

    // Listen for incoming messages in real-time
    final appState = Provider.of<AppState>(context, listen: false);

    // Mark as read when opening
    if (_selectedPeerId != null) {
      appState.markChatAsRead(_selectedPeerId!);
    }

    _incomingMessageSubscription =
        appState.meshRouter.onMessageReceived.listen((chatMessage) {
      // Only add if this message is from the currently selected peer
      if (_selectedPeerId != null && chatMessage.peerId == _selectedPeerId) {
        // Mark as read immediately since we are viewing it
        appState.markChatAsRead(_selectedPeerId!);

        setState(() {
          _messages.add(chatMessage);
          _sortMessagesChronologically();
        });
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: UiTimerConfig.chatAutoScrollAnimation,
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Listen for local status updates (queue/routing transitions).
    _statusChangeSubscription =
        appState.meshRouter.onMessageStatusChanged.listen((messageId) {
      if (_selectedPeerId == null || !mounted) return;
      _applyStatusUpdate(messageId);
    });

    // File transfer feature removed.
  }

  @override
  void dispose() {
    _incomingMessageSubscription?.cancel();
    _statusChangeSubscription?.cancel();
    _highlightResetTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Peer? _findPeerById(AppState appState, String peerId) {
    for (final peer in appState.activePeers) {
      if (peer.id == peerId) return peer;
    }
    for (final peer in appState.peers) {
      if (peer.id == peerId) return peer;
    }
    return null;
  }

  String _selectedPeerDisplayName(AppState appState) {
    final selectedPeerId = _selectedPeerId;
    if (selectedPeerId == null) return 'Peer';
    final peer = _findPeerById(appState, selectedPeerId);
    if (peer == null ||
        peer.id.length > 40 ||
        peer.displayName.trim().isEmpty) {
      return NameGenerator.generateShortName(selectedPeerId);
    }
    return peer.displayName;
  }

  void _startReply(ChatMessage message) {
    setState(() {
      _replyingTo = message;
    });
  }

  void _cancelReply() {
    if (_replyingTo == null) return;
    setState(() {
      _replyingTo = null;
    });
  }

  void _sortMessagesChronologically() {
    _messages.sort((a, b) {
      final timestampOrder = a.timestamp.compareTo(b.timestamp);
      if (timestampOrder != 0) return timestampOrder;
      return a.id.compareTo(b.id);
    });
  }

  String _replySnippet(String content) {
    final compact = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 80) return compact;
    return '${compact.substring(0, 80)}...';
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

  Future<void> _jumpToRepliedMessage(String? targetMessageId) async {
    if (!mounted || targetMessageId == null || targetMessageId.isEmpty) return;

    final targetIndex = _messages.indexWhere((m) => m.id == targetMessageId);
    if (targetIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original replied message not found')),
      );
      return;
    }

    final targetKey = _messageKeyFor(targetMessageId);
    if (_scrollController.hasClients && _messages.length > 1) {
      final maxOffset = _scrollController.position.maxScrollExtent;
      final fraction = targetIndex / (_messages.length - 1);
      final roughOffset = (maxOffset * fraction).clamp(0.0, maxOffset);
      await _scrollController.animateTo(
        roughOffset,
        duration: UiTimerConfig.chatAutoScrollAnimation,
        curve: Curves.easeOut,
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
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
    });
  }

  String _replyAuthorLabelForStored(AppState appState, String? replyPeerId) {
    if (replyPeerId == null || replyPeerId.isEmpty) {
      return 'Reply';
    }
    final localPeerId = appState.publicKey;
    if (localPeerId != null && replyPeerId == localPeerId) {
      return 'You';
    }
    if (_selectedPeerId != null && replyPeerId == _selectedPeerId) {
      return _selectedPeerDisplayName(appState);
    }
    final peer = _findPeerById(appState, replyPeerId);
    if (peer != null && peer.displayName.trim().isNotEmpty) {
      return peer.displayName;
    }
    return NameGenerator.generateShortName(replyPeerId);
  }

  Future<void> _loadMessages() async {
    if (_selectedPeerId == null || !mounted) return;

    setState(() {
      _isLoading = true;
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final messages = await appState.db.getChatMessages(_selectedPeerId!);

    if (!mounted) return;

    setState(() {
      _messages = messages;
      _isLoading = false;
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _applyStatusUpdate(String messageId) async {
    if (_selectedPeerId == null || !mounted) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final updated = await appState.db.getChatMessageById(messageId);
    if (updated == null || !mounted) return;
    if (updated.peerId != _selectedPeerId) return;

    final existingIndex = _messages.indexWhere((m) => m.id == messageId);
    if (existingIndex == -1) {
      setState(() {
        _messages.add(updated);
        _sortMessagesChronologically();
      });
      return;
    }

    final existing = _messages[existingIndex];
    if (existing.status == updated.status &&
        existing.isRead == updated.isRead &&
        existing.hopCount == updated.hopCount) {
      return;
    }

    setState(() {
      _messages[existingIndex] = updated;
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _selectedPeerId == null) {
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final soundEnabled =
        Provider.of<MenuSettingsController>(context, listen: false)
            .notifications
            .sound;
    final content = _messageController.text.trim();
    final replyTarget = _replyingTo;
    final localPeerId = appState.publicKey ?? 'localpeer';
    final prefix = localPeerId.length >=
            MessageLimits.generatedIdSenderPrefixLength
        ? localPeerId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
        : localPeerId;
    final compactUuid = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    final messageId = '${prefix}_$compactUuid';
    final replyToPeerId = replyTarget == null
        ? null
        : (replyTarget.isSentByMe ? localPeerId : _selectedPeerId!);
    final payload = ChatPayload(
      text: content,
      replyToMessageId: replyTarget?.id,
      replyToContent:
          replyTarget == null ? null : _replySnippet(replyTarget.content),
      replyToPeerId: replyToPeerId,
    );
    final wireContent = payload.toWire();

    // Create chat message
    final chatMessage = ChatMessage(
      id: messageId,
      peerId: _selectedPeerId!,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSentByMe: true,
      status: MessageStatus.sending,
      isRead: true, // Sent messages are always read
      replyToMessageId: replyTarget?.id,
      replyToContent:
          replyTarget == null ? null : _replySnippet(replyTarget.content),
      replyToPeerId: replyToPeerId,
    );

    // Save to database
    await appState.db.insertChatMessage(chatMessage);

    // Update UI
    setState(() {
      _messages.add(chatMessage);
      _sortMessagesChronologically();
      _messageController.clear();
      _replyingTo = null;
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: UiTimerConfig.chatAutoScrollAnimation,
          curve: Curves.easeOut,
        );
      }
    });

    // Send via mesh router
    final result = await appState.meshRouter.sendMessage(
      recipientPeerId: _selectedPeerId!,
      content: wireContent,
      priority: MessagePriority.normal,
      messageId: messageId,
    );

    // Update message status
    MessageStatus newStatus;
    switch (result) {
      case SendResult.routed:
        newStatus = MessageStatus.routing;
        if (soundEnabled) {
          unawaited(_notificationSoundService.playSentTick());
        }
        break;
      case SendResult.noRoute:
      case SendResult.queued:
        newStatus = MessageStatus.queued;
        break;
      default:
        newStatus = MessageStatus.failed;
    }

    await appState.db.updateMessageStatus(
      messageId,
      newStatus,
      clearHopCount: true,
    );
    if (!mounted) return;

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    setState(() {
      final old = _messages[index];
      _messages[index] = ChatMessage(
        id: old.id,
        peerId: old.peerId,
        content: old.content,
        timestamp: old.timestamp,
        isSentByMe: old.isSentByMe,
        status: newStatus,
        isRead: old.isRead,
        hopCount: null,
        replyToMessageId: old.replyToMessageId,
        replyToContent: old.replyToContent,
        replyToPeerId: old.replyToPeerId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    // Get peer name
    String peerName = 'Select a peer';
    String peerInitials = '?';
    if (_selectedPeerId != null) {
      final selectedPeerId = _selectedPeerId!;
      final peer = _findPeerById(appState, selectedPeerId);

      if (peer == null ||
          peer.id.length > 40 ||
          peer.displayName.trim().isEmpty) {
        peerName = NameGenerator.generateShortName(selectedPeerId);
      } else {
        peerName = peer.displayName;
      }
      peerInitials = NameGenerator.generateInitials(selectedPeerId);
    }

    final isConnected = _selectedPeerId != null &&
        appState.meshRouter.getConnectedPeerIds().contains(_selectedPeerId);
    final selectedPeerId = _selectedPeerId;
    final hasMeshLink =
        selectedPeerId != null && appState.isPeerTransportLinked(selectedPeerId);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_selectedPeerId != null) ...[
              // Peer avatar
              Stack(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.15),
                    child: Text(
                      peerInitials,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  if (isConnected)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.bgDeep, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_selectedPeerId != null)
                    Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 10,
                          color: AppTheme.primary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'End-to-end encrypted',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.primary.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          hasMeshLink ? Icons.hub_rounded : Icons.hub_outlined,
                          size: 10,
                          color: hasMeshLink
                              ? AppTheme.online
                              : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          hasMeshLink ? 'Mesh link active' : 'Mesh',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: hasMeshLink
                                ? AppTheme.online
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_selectedPeerId == null)
            IconButton(
              icon: const Icon(Icons.person_add_rounded),
              onPressed: () => _showPeerSelector(appState),
            ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _collapseExpandedMessages,
        child: Column(
          children: [
          // Messages list
          Expanded(
            child: _selectedPeerId == null
                ? _buildNoPeerSelected(appState)
                : _isLoading
                    ? const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.primary),
                      )
                    : _buildMessagesList(appState),
          ),
          // Message input
          if (_selectedPeerId != null)
            _buildMessageInput(appState),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPeerSelected(AppState appState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 56,
              color: AppTheme.accent.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Select a peer to chat',
            style: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your messages are end-to-end encrypted',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => _showPeerSelector(appState),
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Select Peer'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList(AppState appState) {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: AppTheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Start a conversation',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Messages are end-to-end encrypted\nand routed over mesh automatically',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final showDateHeader = index == 0 ||
            !_isSameDay(
              _messages[index - 1].timestamp,
              message.timestamp,
            );

        return Column(
          children: [
            if (showDateHeader) _buildDateSeparator(message.timestamp),
            Dismissible(
              key: ValueKey('reply_${message.id}'),
              direction: DismissDirection.startToEnd,
              dismissThresholds: const {
                DismissDirection.startToEnd: 0.25,
              },
              confirmDismiss: (_) async {
                _startReply(message);
                return false;
              },
              background: _buildReplySwipeBackground(),
              child: _buildMessageBubble(message, appState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReplySwipeBackground() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.reply_rounded,
            size: 18,
            color: AppTheme.primary.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 6),
          Text(
            'Reply',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, AppState appState) {
    final isMe = message.isSentByMe;
    final isHighlighted = _highlightedMessageId == message.id;
    final messageTextStyle = GoogleFonts.inter(
      fontSize: 14,
      color: isMe ? Colors.white : AppTheme.textPrimary,
      height: 1.4,
    );
    final lineLimit = _lineLimitForMessage(message.id);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: _messageKeyFor(message.id),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.accentPurple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMe ? null : AppTheme.bgSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft:
                isMe ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight:
                isMe ? const Radius.circular(4) : const Radius.circular(18),
          ),
          border: Border.all(
            color: isHighlighted
                ? AppTheme.warning.withValues(alpha: 0.85)
                : (isMe
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.06)),
            width: isHighlighted ? 1.5 : 1.0,
          ),
          boxShadow: isHighlighted
              ? [
                  BoxShadow(
                    color: AppTheme.warning.withValues(alpha: 0.30),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe && message.hopCount != null) ...[
              _buildHopIndicator(message.hopCount!, isMe),
              const SizedBox(height: 6),
            ],
            if (message.replyToMessageId != null ||
                (message.replyToContent != null &&
                    message.replyToContent!.isNotEmpty)) ...[
              GestureDetector(
                onTap: () => _jumpToRepliedMessage(message.replyToMessageId),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppTheme.bgDeep.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(
                      left: BorderSide(
                        color: isMe ? Colors.white70 : AppTheme.primary,
                        width: 3,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _replyAuthorLabelForStored(
                            appState, message.replyToPeerId),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.95)
                              : AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message.replyToContent ?? '[Message]',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.85)
                              : AppTheme.textSecondary,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final painter = TextPainter(
                  text: TextSpan(
                    text: message.content,
                    style: messageTextStyle,
                  ),
                  maxLines: lineLimit,
                  textDirection: TextDirection.ltr,
                )..layout(maxWidth: constraints.maxWidth);

                final hasMore = painter.didExceedMaxLines;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.content,
                      maxLines: lineLimit,
                      overflow: TextOverflow.ellipsis,
                      style: messageTextStyle,
                    ),
                    if (hasMore) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _expandMessageLines(message.id),
                        child: Text(
                          'Read more...',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.9)
                                : AppTheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.7)
                        : AppTheme.textSecondary,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _getStatusIcon(message.status),
                    size: 15,
                    color: _getStatusColor(message.status),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.access_time_rounded;
      case MessageStatus.queued:
        return Icons.schedule_send_rounded;
      case MessageStatus.routing:
        return Icons.alt_route_rounded;
      case MessageStatus.sent:
        return Icons.alt_route_rounded;
      case MessageStatus.delivered:
      case MessageStatus.seen:
        return Icons.done_all_rounded;
      case MessageStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color _getStatusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.failed:
        return AppTheme.danger;
      case MessageStatus.delivered:
      case MessageStatus.seen:
        return Colors.white;
      case MessageStatus.sending:
      case MessageStatus.queued:
      case MessageStatus.routing:
      case MessageStatus.sent:
        return Colors.white.withValues(alpha: 0.55);
    }
  }

  Widget _buildHopIndicator(int hopCount, bool isMe) {
    final accentColor = isMe
        ? Colors.white.withValues(alpha: 0.85)
        : AppTheme.accent.withValues(alpha: 0.9);
    final hopLabel = hopCount == 1 ? '1 hop' : '$hopCount hops';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.alt_route_rounded,
          size: 12,
          color: accentColor,
        ),
        const SizedBox(width: 4),
        Text(
          hopLabel,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: accentColor,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  bool _isSameDay(int aTimestamp, int bTimestamp) {
    final a = DateTime.fromMillisecondsSinceEpoch(aTimestamp);
    final b = DateTime.fromMillisecondsSinceEpoch(bTimestamp);
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateSeparatorLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    if (date.year == yesterday.year &&
        date.month == yesterday.month &&
        date.day == yesterday.day) {
      return 'Yesterday';
    }

    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildDateSeparator(int timestamp) {
    final label = _formatDateSeparatorLabel(timestamp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput(AppState appState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
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
                  border: const Border(
                    left: BorderSide(
                      color: AppTheme.primary,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _replyingTo!.isSentByMe
                                ? 'Replying to You'
                                : 'Replying to ${_selectedPeerDisplayName(appState)}',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _replySnippet(_replyingTo!.content),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: _cancelReply,
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: _selectedPeerId == null ? null : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DirectTransferScreen(peerId: _selectedPeerId!),
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.attach_file_rounded,
                    color: _selectedPeerId == null ? AppTheme.textSecondary : AppTheme.primary,
                  ),
                  tooltip: 'Transfers & Add Files',
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06)),
                    ),
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: _replyingTo == null
                            ? 'Type a message...'
                            : 'Type a reply...',
                        hintStyle: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                      ),
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded,
                        color: AppTheme.bgDeep, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPeerSelector(AppState appState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final peers = appState.peersWithApp;

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a peer',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              if (peers.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Text(
                      'No peers available',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary),
                    ),
                  ),
                )
              else
                ...peers.map((peer) {
                  final name = peer.id.length > 40
                      ? NameGenerator.generateShortName(peer.id)
                      : peer.displayName;
                  final peerInitials = NameGenerator.generateInitials(peer.id);
                  final avatarHue = (peer.id.hashCode % 360).abs().toDouble();
                  final avatarColor =
                      HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: avatarColor.withValues(alpha: 0.15),
                        child: Text(
                          peerInitials,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: avatarColor,
                          ),
                        ),
                      ),
                      title: Text(
                        name,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        peer.address,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      onTap: () {
                        setState(() {
                          _selectedPeerId = peer.id;
                          _replyingTo = null;
                        });
                        Navigator.pop(context);
                        _loadMessages();
                      },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
