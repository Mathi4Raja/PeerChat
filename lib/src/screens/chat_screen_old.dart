import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../services/mesh_router_service.dart';
import '../models/mesh_message.dart';
import '../utils/name_generator.dart';

class ChatScreen extends StatefulWidget {
  final String? preselectedPeerId;
  
  const ChatScreen({super.key, this.preselectedPeerId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedPeerId;
  MessagePriority _priority = MessagePriority.normal;

  @override
  void initState() {
    super.initState();
    // Set preselected peer if provided
    _selectedPeerId = widget.preselectedPeerId;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Message'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // Peer selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Recipient',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedPeerId,
                      hint: const Text('Choose a peer'),
                      items: appState.peers.map((peer) {
                        // Generate name from peer's public key (ID)
                        final peerName = NameGenerator.generateShortName(peer.id);
                        return DropdownMenuItem(
                          value: peer.id,
                          child: Text(
                            peerName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPeerId = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Priority selection
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Message Priority',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<MessagePriority>(
                      segments: const [
                        ButtonSegment(
                          value: MessagePriority.low,
                          label: Text('Low'),
                          icon: Icon(Icons.arrow_downward),
                        ),
                        ButtonSegment(
                          value: MessagePriority.normal,
                          label: Text('Normal'),
                          icon: Icon(Icons.remove),
                        ),
                        ButtonSegment(
                          value: MessagePriority.high,
                          label: Text('High'),
                          icon: Icon(Icons.arrow_upward),
                        ),
                      ],
                      selected: {_priority},
                      onSelectionChanged: (Set<MessagePriority> newSelection) {
                        setState(() {
                          _priority = newSelection.first;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Message input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Message',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _messageController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Type your message here...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Send button
            ElevatedButton.icon(
              onPressed: _selectedPeerId == null || _messageController.text.isEmpty
                  ? null
                  : () async {
                      final result = await appState.meshRouter.sendMessage(
                        recipientPeerId: _selectedPeerId!,
                        content: _messageController.text,
                        priority: _priority,
                      );

                      if (!mounted) return;

                      String message;
                      Color color;
                      
                      switch (result) {
                        case SendResult.routeFound:
                          message = 'Message sent successfully!';
                          color = Colors.green;
                          break;
                        case SendResult.queued:
                          message = 'Message queued (no route available)';
                          color = Colors.orange;
                          break;
                        case SendResult.noRoute:
                          message = 'No route to destination';
                          color = Colors.red;
                          break;
                        case SendResult.failed:
                          message = 'Failed to send message';
                          color = Colors.red;
                          break;
                      }

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(message),
                          backgroundColor: color,
                        ),
                      );

                      if (result == SendResult.routeFound || result == SendResult.queued) {
                        _messageController.clear();
                      }
                    },
              icon: const Icon(Icons.send),
              label: const Text('Send Message'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 16),
            
            // Info text
            const Text(
              'Messages are encrypted end-to-end and may route through intermediate devices to reach the destination.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
