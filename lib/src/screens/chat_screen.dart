import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../app_state.dart';
import '../services/mesh_router_service.dart';
import '../models/mesh_message.dart';
import '../models/chat_message.dart';
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
    appState.meshRouter.onMessageStatusChanged.listen((messageId) {
      if (_selectedPeerId != null) {
        // Reload all messages to update status icons
        _loadMessages();
      }
    });
  }

  @override
  void dispose() {
    _incomingMessageSubscription?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    if (_selectedPeerId == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    final appState = Provider.of<AppState>(context, listen: false);
    final messages = await appState.db.getChatMessages(_selectedPeerId!);
    
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
        }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peerName, style: const TextStyle(fontSize: 16)),
            if (_selectedPeerId != null)
              const Text(
                'End-to-end encrypted',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          if (_selectedPeerId == null)
            IconButton(
              icon: const Icon(Icons.person),
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
                    ? const Center(child: CircularProgressIndicator())
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
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Select a peer to start chatting',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showPeerSelector(appState),
            icon: const Icon(Icons.person),
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
            Icon(Icons.message_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Send a message to start the conversation',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
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
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _getStatusIcon(message.status),
                    size: 14,
                    color: message.status == MessageStatus.seen ? Colors.blue : Colors.grey[600],
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
        return Icons.access_time;
      case MessageStatus.routing:
        return Icons.alt_route;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.delivered:
      case MessageStatus.seen:
        return Icons.done_all;
      case MessageStatus.failed:
        return Icons.error_outline;
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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.blue,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _showPeerSelector(AppState appState) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final peers = appState.peersWithApp;
        
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a peer to chat with',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (peers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No peers available'),
                )
              else
                ...peers.map((peer) {
                  final name = peer.id.length > 40
                      ? NameGenerator.generateShortName(peer.id)
                      : peer.displayName;
                  
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(name),
                    subtitle: Text(peer.address),
                    onTap: () {
                      setState(() {
                        _selectedPeerId = peer.id;
                      });
                      Navigator.pop(context);
                      _loadMessages();
                    },
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
