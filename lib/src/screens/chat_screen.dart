import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../services/mesh_router_service.dart';
import '../models/mesh_message.dart';
import '../models/chat_message.dart';
import '../theme.dart';
import '../utils/name_generator.dart';

class ChatScreen extends StatefulWidget {
  final String? preselectedPeerId;
  
  const ChatScreen({super.key, this.preselectedPeerId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _selectedPeerId;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  StreamSubscription<ChatMessage>? _incomingMessageSubscription;
  StreamSubscription<String>? _statusChangeSubscription;

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

    _incomingMessageSubscription = appState.meshRouter.onMessageReceived.listen((chatMessage) {
      // Only add if this message is from the currently selected peer
      if (_selectedPeerId != null && chatMessage.peerId == _selectedPeerId) {
        // Mark as read immediately since we are viewing it
        appState.markChatAsRead(_selectedPeerId!);

        setState(() {
          _messages.add(chatMessage);
        });
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Listen for status updates (ACKs, read receipts)
    _statusChangeSubscription = appState.meshRouter.onMessageStatusChanged.listen((messageId) {
      if (_selectedPeerId != null && mounted) {
        // Reload all messages to update status icons
        _loadMessages();
      }
    });
  }

  @override
  void dispose() {
    _incomingMessageSubscription?.cancel();
    _statusChangeSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _selectedPeerId == null) {
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    final content = _messageController.text.trim();
    final messageId = const Uuid().v4();
    
    // Create chat message
    final chatMessage = ChatMessage(
      id: messageId,
      peerId: _selectedPeerId!,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSentByMe: true,
      status: MessageStatus.sending,
      isRead: true, // Sent messages are always read
    );
    
    // Save to database
    await appState.db.insertChatMessage(chatMessage);
    
    // Update UI
    setState(() {
      _messages.add(chatMessage);
      _messageController.clear();
    });
    
    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    
    // Send via mesh router
    final result = await appState.meshRouter.sendMessage(
      recipientPeerId: _selectedPeerId!,
      content: content,
      priority: MessagePriority.normal,
      messageId: messageId,
    );
    
    // Update message status
    MessageStatus newStatus;
    switch (result) {
      case SendResult.direct:
        newStatus = MessageStatus.sent;
        break;
      case SendResult.routed:
        newStatus = MessageStatus.routing;
        break;
      case SendResult.queued:
        newStatus = MessageStatus.sending;
        break;
      default:
        newStatus = MessageStatus.failed;
    }
    
    await appState.db.updateMessageStatus(messageId, newStatus);
    
    // Reload messages to show updated status
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
    // Get peer name
    String peerName = 'Select a peer';
    String peerInitials = '?';
    if (_selectedPeerId != null) {
      final peer = appState.activePeers.firstWhere(
        (p) => p.id == _selectedPeerId,
        orElse: () => appState.peers.firstWhere(
          (p) => p.id == _selectedPeerId!,
          orElse: () => null as dynamic,
        ),
      );
      peerName = peer.id.length > 40 
          ? NameGenerator.generateShortName(peer.id)
          : peer.displayName;
      peerInitials = NameGenerator.generateInitials(peer.id);
    }

    final isConnected = _selectedPeerId != null &&
        appState.meshRouter.getConnectedPeerIds().contains(_selectedPeerId);

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
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _selectedPeerId == null
                ? _buildNoPeerSelected(appState)
                : _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primary),
                      )
                    : _buildMessagesList(),
          ),
          
          // Message input
          if (_selectedPeerId != null) _buildMessageInput(),
        ],
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

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: AppTheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send the first encrypted message',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
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
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.isSentByMe;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF00ACC1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isMe ? null : AppTheme.bgSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isMe ? const Radius.circular(18) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(18),
          ),
          border: isMe
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isMe ? Colors.white : AppTheme.textPrimary,
                height: 1.4,
              ),
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
                    color: message.status == MessageStatus.seen
                        ? const Color(0xFFFFD54F) // gold — premium and visible on teal gradient
                        : (message.status == MessageStatus.delivered
                            ? Colors.white
                            : (message.status == MessageStatus.failed
                                ? AppTheme.danger
                                : Colors.white.withValues(alpha: 0.55))),
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
      case MessageStatus.routing:
        return Icons.alt_route_rounded;
      case MessageStatus.sent:
        return Icons.check_rounded;
      case MessageStatus.delivered:
      case MessageStatus.seen:
        return Icons.done_all_rounded;
      case MessageStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildMessageInput() {
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
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: TextField(
                  controller: _messageController,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
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
                  maxLines: null,
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
                icon: const Icon(Icons.send_rounded, color: AppTheme.bgDeep, size: 20),
                onPressed: _sendMessage,
              ),
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
                  final avatarColor = HSLColor.fromAHSL(1, avatarHue, 0.6, 0.45).toColor();
                  
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
