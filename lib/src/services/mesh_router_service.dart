import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sodium/sodium.dart';
import 'crypto_service.dart';
import 'db_service.dart';
import 'discovery_service.dart';
import 'message_manager.dart';
import 'route_manager.dart';
import 'message_queue.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'delivery_ack_handler.dart';
import 'transport_service.dart';
import 'bluetooth_transport.dart';
import 'wifi_transport.dart';
import 'connection_manager.dart';
import '../models/mesh_message.dart';
import '../models/queued_message.dart';
import '../models/peer.dart';
import '../models/chat_message.dart';
import '../models/handshake_message.dart';

enum SendResult {
  queued,
  routeFound,
  noRoute,
  failed,
}

class RoutingStats {
  final int totalRoutes;
  final int queuedMessages;
  final int pendingAcks;
  final int blockedPeers;

  RoutingStats({
    required this.totalRoutes,
    required this.queuedMessages,
    required this.pendingAcks,
    required this.blockedPeers,
  });
}

class MeshRouterService extends ChangeNotifier {
  final Sodium _sodium;
  final DBService _db;
  final DiscoveryService _discovery;
  
  late final CryptoService _cryptoService;
  late final DeduplicationCache _deduplicationCache;
  late final SignatureVerifier _signatureVerifier;
  late final MessageQueue _messageQueue;
  late final RouteManager _routeManager;
  late final DeliveryAckHandler _deliveryAckHandler;
  late final MessageManager _messageManager;
  late final MultiTransportService _transportService;
  late final ConnectionManager _connectionManager;
  WiFiTransport? _wifiTransport;
  
  Timer? _maintenanceTimer;
  Timer? _queueProcessingTimer;
  StreamSubscription? _peerDiscoverySubscription;
  StreamSubscription? _transportMessageSubscription;

  MeshRouterService(this._sodium, this._db, this._discovery);
  
  // Update local name for WiFi Direct advertising
  void updateLocalName(String name) {
    _wifiTransport?.setLocalIdentity(_cryptoService.localPeerId, name);
    _connectionManager.setDisplayName(name);
  }
  
  // Handle incoming transport message (could be handshake or mesh message)
  Future<void> _handleTransportMessage(TransportMessage transportMsg) async {
    try {
      // Try to parse as handshake first
      final handshake = HandshakeMessage.fromBytes(transportMsg.data);
      if (handshake != null) {
        debugPrint('Received handshake from ${transportMsg.fromPeerId}');
        await _connectionManager.handleHandshake(transportMsg.fromPeerId, handshake);
        
        // Send our handshake back if we haven't already
        if (!_connectionManager.isHandshakeComplete(transportMsg.fromPeerId)) {
          await _connectionManager.onConnectionEstablished(transportMsg.fromPeerId);
        }
        
        notifyListeners();
        return;
      }
      
      // Not a handshake, treat as mesh message
      await receiveMessage(transportMsg.data, transportMsg.fromAddress);
    } catch (e) {
      debugPrint('Error handling transport message: $e');
    }
  }

  // Initialize service and start listening to peer discovery
  Future<void> init() async {
    // Initialize crypto service
    _cryptoService = CryptoService(_sodium);
    await _cryptoService.init();

    // Initialize components
    // Initialize transport layer FIRST so we can pass it to managers
    _transportService = MultiTransportService();
    
    // Create Bluetooth transport with connection callback
    final bluetoothTransport = BluetoothTransport();
    bluetoothTransport.onConnectionEstablished = (transportId) {
      debugPrint('Bluetooth connection established: $transportId');
      _connectionManager.onConnectionEstablished(transportId);
    };
    _transportService.addTransport(bluetoothTransport);
    
    // Create WiFi transport with peer discovery and connection callbacks
    final wifiTransport = WiFiTransport(
      onPeerDiscovered: (peerId, address) {
        _discovery.addWiFiDirectPeer(peerId, address);
      },
    );
    wifiTransport.onConnectionEstablished = (transportId) {
      debugPrint('WiFi Direct connection established: $transportId');
      _connectionManager.onConnectionEstablished(transportId);
    };
    // Note: Name will be set later via updateLocalName() after AppState generates it
    wifiTransport.setLocalIdentity(
      _cryptoService.localPeerId,
      'PeerChat User',
    );
    _transportService.addTransport(wifiTransport);
    
    // Store WiFi transport reference for later name updates
    _wifiTransport = wifiTransport;
    
    await _transportService.init();

    // Set up connection manager callback for sending handshakes
    _connectionManager.onSendHandshake = (transportId, data) async {
      debugPrint('Sending handshake to $transportId');
      await _transportService.sendMessage(transportId, data);
    };

    // Listen to transport messages
    _transportMessageSubscription = _transportService.onMessageReceived.listen((transportMsg) {
      _handleTransportMessage(transportMsg);
    });

    // Listen to peer discovery events
    _peerDiscoverySubscription = _discovery.onPeerFound.listen(_onPeerConnected);

    // Start background maintenance tasks
    _startMaintenanceTasks();
    _startQueueProcessing();
  }

  // Send a message to a destination peer
  Future<SendResult> sendMessage({
    required String recipientPeerId,
    required String content,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    try {
      debugPrint('=== SEND MESSAGE START ===');
      debugPrint('Recipient: $recipientPeerId');
      debugPrint('Content: $content');
      
      // Get recipient's public key
      final recipientPublicKey = await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) {
        debugPrint('ERROR: No public key found for recipient $recipientPeerId');
        return SendResult.failed;
      }
      debugPrint('Public key found for recipient');

      // Create message
      final message = await _messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
      );
      debugPrint('Message created: ${message.messageId}');

      // Track pending acknowledgment
      await _deliveryAckHandler.trackPendingAck(message.messageId, recipientPeerId);

      // Try to forward message
      debugPrint('Attempting to forward message...');
      final forwarded = await _forwardMessageViaTransport(message);
      
      debugPrint('Message forwarded: $forwarded');
      debugPrint('=== SEND MESSAGE END ===');
      
      notifyListeners();
      
      return forwarded ? SendResult.routeFound : SendResult.queued;
    } catch (e) {
      debugPrint('ERROR sending message: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
      return SendResult.failed;
    }
  }

  // Forward message via transport layer
  Future<bool> _forwardMessageViaTransport(MeshMessage message) async {
    debugPrint('=== FORWARD MESSAGE ===');
    debugPrint('Looking for route to: ${message.recipientPeerId}');
    
    // Get next hop (crypto peer ID)
    final nextHopCryptoId = await _routeManager.getNextHop(message.recipientPeerId);
    
    if (nextHopCryptoId == null) {
      debugPrint('No route found, queuing message');
      // No route available - queue message and initiate discovery
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      
      // Initiate route discovery
      _routeManager.discoverRoute(message.recipientPeerId);
      
      return false;
    }

    debugPrint('Next hop (crypto ID): $nextHopCryptoId');
    
    // Map crypto ID to transport ID
    final transportId = _connectionManager.getTransportId(nextHopCryptoId);
    if (transportId == null) {
      debugPrint('No transport ID mapping for $nextHopCryptoId');
      debugPrint('Available mappings: ${_connectionManager.getConnectedCryptoPeerIds()}');
      
      // Queue message - connection might be established soon
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      return false;
    }
    
    debugPrint('Transport ID: $transportId');
    debugPrint('Sending via transport layer...');
    
    // Send via transport layer using transport ID
    final sent = await _transportService.sendMessage(transportId, message.toBytes());
    
    if (sent) {
      debugPrint('Transport layer reports: SENT');
      await _routeManager.markRouteSuccess(message.recipientPeerId, nextHopCryptoId);
      return true;
    } else {
      debugPrint('Transport layer reports: FAILED');
      // Queue message if send failed
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      await _routeManager.markRouteFailed(message.recipientPeerId, nextHopCryptoId);
      return false;
    }
  }

  // Process an incoming message from transport layer
  Future<void> receiveMessage(Uint8List rawMessage, String fromPeerAddress) async {
    try {
      final message = MeshMessage.fromBytes(rawMessage);
      final result = await _messageManager.processMessage(message, fromPeerAddress);
      
      if (result == ProcessResult.delivered) {
        // Decrypt and deliver to application layer
        final content = await _messageManager.decryptContent(message);
        if (content != null) {
          _deliverToApplication(message, content);
        }
      } else if (result == ProcessResult.forwarded || result == ProcessResult.queued) {
        // Message was forwarded or queued for relay
        await _forwardMessageViaTransport(message);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error receiving message: $e');
    }
  }

  // Handle peer connectivity changes
  void _onPeerConnected(Peer peer) async {
    await _routeManager.onPeerConnected(peer);
    
    // Check if there are queued messages for this peer
    if (await _messageQueue.hasPendingMessagesForPeer(peer.id)) {
      await _processQueueForPeer(peer.id);
    }
    
    notifyListeners();
  }

  void _onPeerDisconnected(String peerId) async {
    await _routeManager.onPeerDisconnected(peerId);
    notifyListeners();
  }

  // Start periodic maintenance tasks
  void _startMaintenanceTasks() {
    _maintenanceTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      try {
        await _routeManager.expireStaleRoutes();
        await _messageQueue.removeExpired();
        await _deduplicationCache.cleanup();
        await _signatureVerifier.unblockExpiredPeers();
        await _deliveryAckHandler.cleanupOldAcks();
        notifyListeners();
      } catch (e) {
        debugPrint('Error in maintenance tasks: $e');
      }
    });
  }

  // Start queue processing
  void _startQueueProcessing() {
    _queueProcessingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        await _processQueue();
      } catch (e) {
        debugPrint('Error processing queue: $e');
      }
    });
  }

  // Process message queue
  Future<void> _processQueue() async {
    final queuedMessages = await _messageQueue.getAllQueued();
    
    for (final queuedMessage in queuedMessages) {
      // Check if message expired
      if (queuedMessage.isExpired) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        continue;
      }

      // Try to send message via transport
      final sent = await _transportService.sendMessage(
        queuedMessage.nextHopPeerId,
        queuedMessage.message.toBytes(),
      );

      if (sent) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _routeManager.markRouteSuccess(
          queuedMessage.message.recipientPeerId,
          queuedMessage.nextHopPeerId,
        );
      } else {
        await _messageQueue.updateAttempt(queuedMessage.message.messageId);
      }
    }
  }

  // Process queue for specific peer
  Future<void> _processQueueForPeer(String peerId) async {
    final messages = await _messageQueue.getMessagesForPeer(peerId);
    
    for (final queuedMessage in messages) {
      final sent = await _transportService.sendMessage(
        peerId,
        queuedMessage.message.toBytes(),
      );

      if (sent) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
      }
    }
  }

  // Deliver message to application layer
  void _deliverToApplication(MeshMessage message, String content) async {
    debugPrint('Message received from ${message.senderPeerId}: $content');
    
    // Save to chat messages database
    final chatMessage = ChatMessage(
      id: message.messageId,
      peerId: message.senderPeerId,
      content: content,
      timestamp: message.timestamp,
      isSentByMe: false,
      status: MessageStatus.delivered,
    );
    
    await _db.insertChatMessage(chatMessage);
    notifyListeners(); // Notify UI to refresh
  }

  // Expose routing statistics
  Future<RoutingStats> get stats async {
    final routeStats = await _routeManager.getStats();
    final queueStats = await _messageQueue.getStats();
    final ackStats = await _deliveryAckHandler.getStats();
    final sigStats = await _signatureVerifier.getStats();

    return RoutingStats(
      totalRoutes: routeStats['total_routes'] ?? 0,
      queuedMessages: queueStats.totalMessages,
      pendingAcks: ackStats['pending_acks'] ?? 0,
      blockedPeers: sigStats['blocked_peers'] ?? 0,
    );
  }

  // Expose message queue status
  Future<QueueStats> get queueStatus async {
    return await _messageQueue.getStats();
  }

  // Get list of connected peer IDs (crypto IDs)
  List<String> getConnectedPeerIds() {
    return _connectionManager.getConnectedCryptoPeerIds();
  }

  // Cleanup
  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _peerDiscoverySubscription?.cancel();
    _transportMessageSubscription?.cancel();
    _transportService.dispose();
    super.dispose();
  }
}
