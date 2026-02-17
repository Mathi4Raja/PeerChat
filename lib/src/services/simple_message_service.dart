import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'transport_service.dart';
import 'bluetooth_transport.dart';
import 'wifi_transport.dart';
import 'db_service.dart';
import '../models/chat_message.dart';

/// Simplified message service for direct peer-to-peer messaging
/// Bypasses mesh routing and encryption for initial testing
class SimpleMessageService extends ChangeNotifier {
  final DBService _db;
  late final MultiTransportService _transportService;
  StreamSubscription? _transportMessageSubscription;

  SimpleMessageService(this._db);

  Future<void> init() async {
    // Initialize transport layer
    _transportService = MultiTransportService();
    _transportService.addTransport(BluetoothTransport());
    
    final wifiTransport = WiFiTransport(
      onPeerDiscovered: (peerId, address) {
        debugPrint('WiFi peer discovered: $peerId ($address)');
      },
    );
    _transportService.addTransport(wifiTransport);
    
    await _transportService.init();

    // Listen to transport messages
    _transportMessageSubscription = _transportService.onMessageReceived.listen((transportMsg) {
      _handleIncomingMessage(transportMsg);
    });
    
    debugPrint('SimpleMessageService initialized');
  }

  /// Send a simple text message to a peer
  Future<bool> sendMessage(String peerId, String content) async {
    try {
      debugPrint('Sending message to $peerId: $content');
      
      // Create simple JSON message
      final messageData = jsonEncode({
        'type': 'chat',
        'content': content,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      final bytes = Uint8List.fromList(utf8.encode(messageData));
      
      // Send via transport
      final sent = await _transportService.sendMessage(peerId, bytes);
      
      if (sent) {
        debugPrint('Message sent successfully');
      } else {
        debugPrint('Failed to send message - no connection to $peerId');
      }
      
      return sent;
    } catch (e) {
      debugPrint('Error sending message: $e');
      return false;
    }
  }

  /// Handle incoming message from transport layer
  void _handleIncomingMessage(TransportMessage transportMsg) {
    try {
      debugPrint('Received message from ${transportMsg.fromPeerId}');
      
      // Decode message
      final messageJson = jsonDecode(utf8.decode(transportMsg.data));
      
      if (messageJson['type'] == 'chat') {
        final content = messageJson['content'] as String;
        final timestamp = messageJson['timestamp'] as int;
        
        debugPrint('Chat message: $content');
        
        // Save to database
        final chatMessage = ChatMessage(
          id: '${transportMsg.fromPeerId}_$timestamp',
          peerId: transportMsg.fromPeerId,
          content: content,
          timestamp: timestamp,
          isSentByMe: false,
          status: MessageStatus.delivered,
        );
        
        _db.insertChatMessage(chatMessage);
        notifyListeners(); // Notify UI to refresh
      }
    } catch (e) {
      debugPrint('Error handling incoming message: $e');
    }
  }

  /// Get list of connected peer IDs
  List<String> getConnectedPeerIds() {
    return _transportService.getConnectedPeerIds();
  }

  @override
  void dispose() {
    _transportMessageSubscription?.cancel();
    _transportService.dispose();
    super.dispose();
  }
}
