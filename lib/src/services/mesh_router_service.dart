import 'dart:async';
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
import '../models/route.dart' as mesh_route;
import '../models/peer.dart';
import '../models/chat_message.dart';
import '../models/handshake_message.dart';
import 'package:uuid/uuid.dart';

enum SendResult {
  queued,
  direct,
  routed,
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

  // Stream for incoming messages — ChatScreen listens to this
  final StreamController<ChatMessage> _incomingMessageController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessageReceived => _incomingMessageController.stream;

  // Stream for message status updates (IDs of changed messages)
  final StreamController<String> _statusUpdateController =
      StreamController<String>.broadcast();
  Stream<String> get onMessageStatusChanged => _statusUpdateController.stream;

  MeshRouterService(this._sodium, this._db, this._discovery);
  
  // Update local name for WiFi Direct advertising
  void updateLocalName(String name) {
    _wifiTransport?.setLocalIdentity(_cryptoService.localPeerId, name);
    _connectionManager.setDisplayName(name);
  }
  
  // Restart WiFi Direct advertising and discovery
  Future<void> restartWiFiDirect() async {
    debugPrint('Restarting WiFi Direct...');
    await _wifiTransport?.restartWiFiDirect();
  }
  
  // Handle incoming transport message (could be handshake or mesh message)
  Future<void> _handleTransportMessage(TransportMessage transportMsg) async {
    try {
      // Update peer activity for any received data
      await _connectionManager.updatePeerActivity(transportMsg.fromPeerId);
      
      // Check if it's a keepalive packet (2 bytes: 0xFF 0xFF)
      if (transportMsg.data.length == 2 && 
          transportMsg.data[0] == 0xFF && 
          transportMsg.data[1] == 0xFF) {
        // Keepalive - already processed by updatePeerActivity, nothing more to do
        return;
      }
      
      // Try to parse as handshake first
      final handshake = HandshakeMessage.fromBytes(transportMsg.data);
      if (handshake != null) {
        debugPrint('Received handshake from ${transportMsg.fromPeerId}');
        await _connectionManager.handleHandshake(transportMsg.fromPeerId, handshake);
        
        // Send our handshake back if we haven't already
        if (!_connectionManager.isHandshakeComplete(transportMsg.fromPeerId)) {
          await _connectionManager.onConnectionEstablished(transportMsg.fromPeerId);
        }
        
        // ── Post-handshake: add direct route using CRYPTO ID ──
        final cryptoPeerId = handshake.peerId;
        final route = mesh_route.Route(
          destinationPeerId: cryptoPeerId,
          nextHopPeerId: cryptoPeerId,
          hopCount: 1,
          lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
          lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
          successCount: 0,
          failureCount: 0,
        );
        await _routeManager.addRoute(route);
        debugPrint('Direct route added for crypto peer: $cryptoPeerId');
        
        // ── Remove the old transport-ID-based peer entry from DB ──
        // The transport ID (MAC address / endpoint ID) is different from the crypto ID.
        // ConnectionManager already upserts with the crypto ID, so just delete the old one.
        if (transportMsg.fromPeerId != cryptoPeerId) {
          await _db.deletePeer(transportMsg.fromPeerId);
          debugPrint('Cleaned up old transport peer entry: ${transportMsg.fromPeerId}');
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

    // ── Initialize all core services BEFORE transport setup ──
    _deduplicationCache = DeduplicationCache(_db);
    _signatureVerifier = SignatureVerifier(_cryptoService, _db);
    _messageQueue = MessageQueue(_db);
    _deliveryAckHandler = DeliveryAckHandler(_db, _cryptoService);
    _deliveryAckHandler.onStatusChanged = (id) => _statusUpdateController.add(id);
    _connectionManager = ConnectionManager(_db, _cryptoService);
    _connectionManager.onHandshakeComplete = (peerId) async {
      debugPrint('Handshake complete for $peerId - processing full queue');
      await _processQueue();
      notifyListeners();
    };
    
    // Listen to connection manager changes (peer activity updates)
    _connectionManager.addListener(() {
      debugPrint('ConnectionManager changed - notifying UI');
      notifyListeners();
    });

    // Initialize transport layer
    _transportService = MultiTransportService();
    
    // Create Bluetooth transport with connection callback
    final bluetoothTransport = BluetoothTransport();
    bluetoothTransport.onConnectionEstablished = (transportId) {
      debugPrint('Bluetooth connection established: $transportId');
      _connectionManager.onConnectionEstablished(transportId);
    };
    bluetoothTransport.onConnectionLost = (transportId) {
      debugPrint('Bluetooth connection lost: $transportId');
      _connectionManager.onConnectionLost(transportId);
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
    wifiTransport.onConnectionLost = (transportId) {
      debugPrint('WiFi Direct connection lost: $transportId');
      _connectionManager.onConnectionLost(transportId);
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

    // ── Initialize services that depend on transport ──
    _routeManager = RouteManager(
      _db,
      _signatureVerifier,
      _cryptoService,
      (peerId, data) async {
        // Map the crypto peer ID to a transport ID for actual transmission
        final transportId = _connectionManager.getTransportId(peerId);
        if (transportId != null) {
          debugPrint('Route Discovery mapped: $peerId -> $transportId');
          return await _transportService.sendMessage(transportId, data);
        }
        debugPrint('Route Discovery FAILED: No transport mapping for $peerId');
        return false;
      },
    );
    _routeManager.onRouteFound.listen((peerId) async {
      debugPrint('Route found/improved for $peerId - processing full queue');
      await _processQueue();
      notifyListeners();
    });
    _messageManager = MessageManager(
      _cryptoService,
      _routeManager,
      _messageQueue,
      _deduplicationCache,
      _signatureVerifier,
      _deliveryAckHandler,
      (peerId, data) async {
        // Map the crypto peer ID to a transport ID for actual transmission
        final transportId = _connectionManager.getTransportId(peerId);
        if (transportId != null) {
          debugPrint('Relay/ACK mapped: $peerId -> $transportId');
          return await _transportService.sendMessage(transportId, data);
        }
        debugPrint('Relay/ACK FAILED: No transport mapping for $peerId');
        return false;
      },
    );

    // Wire delivery ack handler to signature verifier for public key lookups
    _deliveryAckHandler.setSignatureVerifier(_signatureVerifier);

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
    String? messageId,
  }) async {
    try {
      debugPrint('=== SEND MESSAGE START ===');
      debugPrint('Recipient: $recipientPeerId');
      
      // Get recipient's public key
      final recipientPublicKey = await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) {
        debugPrint('ERROR: No public key found for recipient $recipientPeerId');
        return SendResult.failed;
      }

      // Create message
      final message = await _messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
        messageId: messageId,
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
      
      return forwarded;
    } catch (e) {
      debugPrint('ERROR sending message: $e');
      return SendResult.failed;
    }
  }

  // Send a read receipt for specific messages
  Future<void> sendReadReceipt({
    required String recipientPeerId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;

    try {
      debugPrint('=== SEND READ RECEIPT ===');
      debugPrint('Recipient: $recipientPeerId');
      debugPrint('IDs: $messageIds');

      final recipientPublicKey = await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) return;

      // Create a read receipt content string
      final content = 'READ:${messageIds.join(',')}';
      
      // Get recipient's encryption public key
      final recipientEncryptionKey = await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
      if (recipientEncryptionKey == null) return;

      // Encrypt content
      final encryptedContent = _cryptoService.encryptContent(
        content,
        recipientEncryptionKey,
      );

      final messageId = const Uuid().v4();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final message = MeshMessage(
        messageId: messageId,
        type: MessageType.readReceipt,
        senderPeerId: _cryptoService.localPeerId,
        recipientPeerId: recipientPeerId,
        ttl: 12,
        hopCount: 0,
        priority: MessagePriority.normal,
        timestamp: timestamp,
        encryptedContent: encryptedContent,
        signature: Uint8List(0),
      );

      // Sign the message
      final signature = _cryptoService.signMessage(message.toBytesForSigning());
      
      final signedMessage = MeshMessage(
        messageId: message.messageId,
        type: message.type,
        senderPeerId: message.senderPeerId,
        recipientPeerId: message.recipientPeerId,
        ttl: message.ttl,
        hopCount: message.hopCount,
        priority: message.priority,
        timestamp: message.timestamp,
        encryptedContent: message.encryptedContent,
        signature: signature,
      );

      await _forwardMessageViaTransport(signedMessage);
    } catch (e) {
      debugPrint('Error sending read receipt: $e');
    }
  }

  // Forward message via transport layer
  Future<SendResult> _forwardMessageViaTransport(MeshMessage message) async {
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
      
      return SendResult.noRoute;
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
      return SendResult.queued;
    }
    
    debugPrint('Transport ID: $transportId');
    debugPrint('Sending via transport layer...');
    
    // Send via transport layer using transport ID
    final sent = await _transportService.sendMessage(transportId, message.toBytes());
    
    if (sent) {
      debugPrint('Transport layer reports: SENT');
      await _routeManager.markRouteSuccess(message.recipientPeerId, nextHopCryptoId);
      return nextHopCryptoId == message.recipientPeerId ? SendResult.direct : SendResult.routed;
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
      return SendResult.failed;
    }
  }

  // Process an incoming message from transport layer
  Future<void> receiveMessage(Uint8List rawMessage, String fromPeerAddress) async {
    try {
      final message = MeshMessage.fromBytes(rawMessage);
      
      // --- ROUTE LEARNING ---
      // Learn/Update route back to sender via the peer who just handed us this packet
      final immediateSenderId = _connectionManager.getCryptoPeerId(fromPeerAddress);
      if (immediateSenderId != null) {
        // If we received this from a peer, we now know that senderId is reachable via immediateSenderId
        // hopCount + 1 reflects the distance to us
        final learnedRoute = mesh_route.Route(
          destinationPeerId: message.senderPeerId,
          nextHopPeerId: immediateSenderId,
          hopCount: message.hopCount + 1,
          lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
          lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
          successCount: 1, // We just successfully received from them
          failureCount: 0,
        );
        await _routeManager.addRoute(learnedRoute);
        debugPrint('Learned reverse route to ${message.senderPeerId} via $immediateSenderId (${message.hopCount + 1} hops)');
      }

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
    
    // Process full queue as this peer might be a gateway to multiple destinations
    debugPrint('Peer connected: ${peer.id} - processing full queue');
    await _processQueue();
    
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
    if (queuedMessages.isEmpty) return;
    
    debugPrint('Processing system-wide message queue (${queuedMessages.length} messages)');
    for (final queuedMessage in queuedMessages) {
      // Check if message expired
      if (queuedMessage.isExpired) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        continue;
      }

      // Re-evaluate next hop based on current routing table
      final currentNextHop = await _routeManager.getNextHop(queuedMessage.message.recipientPeerId);
      
      if (currentNextHop == null) {
        // Still no route - ignore for this pass
        continue;
      }

      // Map crypto ID to transport ID
      final transportId = _connectionManager.getTransportId(currentNextHop);
      if (transportId == null) {
        // Routing exists but neighbor connection is not active/handshaked
        continue;
      }

      // Try to send message via transport
      debugPrint('Queue item ${queuedMessage.message.messageId}: found route via $currentNextHop ($transportId)');
      final sent = await _transportService.sendMessage(
        transportId,
        queuedMessage.message.toBytes(),
      );

      if (sent) {
        debugPrint('Successfully sent queued message ${queuedMessage.message.messageId}');
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _routeManager.markRouteSuccess(
          queuedMessage.message.recipientPeerId,
          currentNextHop,
        );
      } else {
        await _messageQueue.updateAttempt(queuedMessage.message.messageId);
        await _routeManager.markRouteFailed(
          queuedMessage.message.recipientPeerId,
          currentNextHop,
        );
      }
    }
  }



  // Deliver message to application layer
  void _deliverToApplication(MeshMessage message, String content) async {
    if (message.type == MessageType.data) {
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
      
      // Publish to stream so ChatScreen updates in real-time
      _incomingMessageController.add(chatMessage);
    } else if (message.type == MessageType.readReceipt) {
      if (content.startsWith('READ:')) {
        final ids = content.substring(5).split(',');
        debugPrint('Read receipt received for messages: $ids');
        for (final id in ids) {
          await _db.updateMessageStatus(id, MessageStatus.seen);
          _statusUpdateController.add(id); // Notify UI of status change
        }
      }
    }
    
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

  // Debug accessors for routing debug UI
  RouteManager get routeManager => _routeManager;
  MessageQueue get messageQueue => _messageQueue;
  MultiTransportService get transportService => _transportService;
  String get localPeerId => _cryptoService.localPeerId;

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
    _incomingMessageController.close();
    _statusUpdateController.close();
    _transportService.dispose();
    super.dispose();
  }
}
