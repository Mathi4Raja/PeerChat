import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sodium/sodium.dart';
import 'crypto_service.dart';
import 'discovery_service.dart';
import 'db_service.dart';
import '../models/chat_message.dart';
import '../models/mesh_message.dart';
import '../models/communication_mode.dart';
import '../models/queued_message.dart';
import '../models/peer.dart';
import '../models/handshake_message.dart';
import '../models/route.dart' as mesh_route;
import 'message_manager.dart';
import 'route_manager.dart';
import 'message_queue.dart';
import 'file_transfer_service.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'delivery_ack_handler.dart';
import 'connection_manager.dart';
import 'transport_service.dart';
import 'wifi_transport.dart';
import 'bluetooth_transport.dart';
import 'package:uuid/uuid.dart';

class MeshRouterService extends ChangeNotifier {
  final DBService _db;
  final DiscoveryService _discovery;
  
  final CryptoService _cryptoService;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  final MessageQueue _messageQueue;
  final RouteManager _routeManager;
  final DeliveryAckHandler _deliveryAckHandler;
  final MessageManager _messageManager;
  final MultiTransportService _transportService;
  final ConnectionManager _connectionManager;
  final FileTransferService _fileTransferService;
  
  WiFiTransport? _wifiTransport;
  
  Timer? _maintenanceTimer;
  Timer? _queueProcessingTimer;
  Timer? _queueDebounceTimer;
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

  MeshRouterService({
    required Sodium sodium,
    required DBService db,
    required DiscoveryService discovery,
    required CryptoService cryptoService,
    required DeduplicationCache deduplicationCache,
    required SignatureVerifier signatureVerifier,
    required MessageQueue messageQueue,
    required RouteManager routeManager,
    required DeliveryAckHandler deliveryAckHandler,
    required MessageManager messageManager,
    required MultiTransportService transportService,
    required ConnectionManager connectionManager,
    required FileTransferService fileTransferService,
  })  : _db = db,
        _discovery = discovery,
        _cryptoService = cryptoService,
        _deduplicationCache = deduplicationCache,
        _signatureVerifier = signatureVerifier,
        _messageQueue = messageQueue,
        _routeManager = routeManager,
        _deliveryAckHandler = deliveryAckHandler,
        _messageManager = messageManager,
        _transportService = transportService,
        _connectionManager = connectionManager,
        _fileTransferService = fileTransferService {
    // Listen for peer connectivity (discovery) changes
    _discovery.onPeerFound.listen(_onPeerConnected);
    
    _deliveryAckHandler.onStatusChanged = (id) => _statusUpdateController.add(id);
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
  }
  
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
        return;
      }
      
      // Try to parse as handshake first
      final handshake = HandshakeMessage.fromBytes(transportMsg.data);
      if (handshake != null) {
        debugPrint('Received handshake from ${transportMsg.fromPeerId}');
        await _connectionManager.handleHandshake(transportMsg.fromPeerId, handshake);
        
        if (!_connectionManager.isHandshakeComplete(transportMsg.fromPeerId)) {
          await _connectionManager.onConnectionEstablished(transportMsg.fromPeerId);
        }
        
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
        
        if (transportMsg.fromPeerId != cryptoPeerId) {
          await _db.deletePeer(transportMsg.fromPeerId);
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
    await _cryptoService.init();

    // Create Bluetooth transport
    final bluetoothTransport = BluetoothTransport();
    bluetoothTransport.onConnectionEstablished = (transportId) {
      _connectionManager.onConnectionEstablished(transportId);
    };
    bluetoothTransport.onConnectionLost = (transportId) {
      _connectionManager.onConnectionLost(transportId);
    };
    _transportService.addTransport(bluetoothTransport);
    
    // Create WiFi transport
    final wifiTransport = WiFiTransport(
      onPeerDiscovered: (peerId, address) {
        _discovery.addWiFiDirectPeer(peerId, address);
      },
    );
    wifiTransport.onConnectionEstablished = (transportId) {
      _connectionManager.onConnectionEstablished(transportId);
    };
    wifiTransport.onConnectionLost = (transportId) {
      _connectionManager.onConnectionLost(transportId);
    };
    wifiTransport.setLocalIdentity(_cryptoService.localPeerId, 'PeerChat User');
    _transportService.addTransport(wifiTransport);
    _wifiTransport = wifiTransport;
    
    await _transportService.init();

    // Set up connection manager callback for sending handshakes
    _connectionManager.onSendHandshake = (transportId, data) async {
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

  /// Generate a globally unique, sender-prefixed message ID.
  String _generateMessageId() {
    final prefix = _cryptoService.localPeerId.substring(0, 8);
    return '${prefix}_${const Uuid().v4()}';
  }

  // Send a message to a destination peer
  Future<SendResult> sendMessage({
    required String recipientPeerId,
    required String content,
    MessagePriority priority = MessagePriority.normal,
    String? messageId,
  }) async {
    try {
      final mode = selectMode(
        destinationId: recipientPeerId,
        connectedPeerIds: getConnectedPeerIds(),
      );

      final msgId = messageId ?? _generateMessageId();
      final recipientPublicKey = await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) return SendResult.failed;

      final message = await _messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
        messageId: msgId,
      );

      await _deliveryAckHandler.trackPendingAck(message.messageId, recipientPeerId);

      switch (mode) {
        case CommunicationMode.direct:
          final result = await _sendDirect(message, recipientPeerId);
          notifyListeners();
          return result;
        case CommunicationMode.mesh:
        case CommunicationMode.emergencyBroadcast:
          final forwarded = await _forwardMessageViaTransport(message);
          notifyListeners();
          return forwarded;
      }
    } catch (e) {
      debugPrint('ERROR sending message: $e');
      return SendResult.failed;
    }
  }

  Future<SendResult> _sendDirect(MeshMessage message, String recipientPeerId) async {
    final transportId = _connectionManager.getTransportId(recipientPeerId);
    if (transportId == null) {
      return _forwardMessageViaTransport(message);
    }

    final sent = await _transportService.sendMessage(transportId, message.toBytes());

    if (sent) {
      await _routeManager.markRouteSuccess(recipientPeerId, recipientPeerId);
      return SendResult.direct;
    } else {
      return _forwardMessageViaTransport(message);
    }
  }

  Future<void> sendReadReceipt({
    required String recipientPeerId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    try {
      final recipientPublicKey = await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) return;

      final content = 'READ:${messageIds.join(',')}';
      final recipientEncryptionKey = await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
      if (recipientEncryptionKey == null) return;

      final encryptedContent = _cryptoService.encryptContent(content, recipientEncryptionKey);
      final messageId = _generateMessageId();

      final message = MeshMessage(
        messageId: messageId,
        type: MessageType.readReceipt,
        senderPeerId: _cryptoService.localPeerId,
        recipientPeerId: recipientPeerId,
        ttl: 12,
        hopCount: 0,
        priority: MessagePriority.normal,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        encryptedContent: encryptedContent,
        signature: Uint8List(0),
      );

      final signature = _cryptoService.signMessage(message.toBytesForSigning());
      final signedMessage = message.copyWithSignature(signature);

      await _forwardMessageViaTransport(signedMessage);
    } catch (e) {
      debugPrint('Error sending read receipt: $e');
    }
  }

  Future<SendResult> _forwardMessageViaTransport(MeshMessage message) async {
    final nextHopCryptoId = await _routeManager.getNextHop(message.recipientPeerId);
    
    if (nextHopCryptoId == null) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      _routeManager.discoverRoute(message.recipientPeerId);
      return SendResult.noRoute;
    }

    final transportId = _connectionManager.getTransportId(nextHopCryptoId);
    if (transportId == null) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      return SendResult.queued;
    }
    
    final sent = await _transportService.sendMessage(transportId, message.toBytes());
    
    if (sent) {
      await _routeManager.markRouteSuccess(message.recipientPeerId, nextHopCryptoId);
      return nextHopCryptoId == message.recipientPeerId ? SendResult.direct : SendResult.routed;
    } else {
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

  Future<void> receiveMessage(Uint8List rawMessage, String fromPeerAddress) async {
    try {
      if (FileTransferService.isFileTransferMessage(rawMessage)) {
        final cryptoId = _connectionManager.getCryptoPeerId(fromPeerAddress);
        if (cryptoId != null) {
          await _fileTransferService.dispatchRawMessage(cryptoId, rawMessage);
          return;
        }
      }

      final message = MeshMessage.fromBytes(rawMessage);
      
      if (_deduplicationCache.hasSeenFingerprint(message.messageId, message.senderPeerId, message.hopCount)) {
        return;
      }
      _deduplicationCache.markFingerprint(message.messageId, message.senderPeerId, message.hopCount);

      final immediateSenderId = _connectionManager.getCryptoPeerId(fromPeerAddress);
      if (immediateSenderId != null) {
        final learnedRoute = mesh_route.Route(
          destinationPeerId: message.senderPeerId,
          nextHopPeerId: immediateSenderId,
          hopCount: message.hopCount + 1,
          lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
          lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
          successCount: 1,
          failureCount: 0,
        );
        await _routeManager.addRoute(learnedRoute);
      }

      final result = await _messageManager.processMessage(message, fromPeerAddress);
      
      if (result == ProcessResult.delivered) {
        final content = await _messageManager.decryptContent(message);
        if (content != null) {
          _deliverToApplication(message, content);
        }
      } else if (result == ProcessResult.forwarded || result == ProcessResult.queued) {
        final nextHop = await _routeManager.getNextHop(message.recipientPeerId);
        if (nextHop != null) {
          await _forwardMessageViaTransport(message);
        } else {
          await _lazyFlood(message, fromPeerAddress);
        }
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error receiving message: $e');
    }
  }

  Future<void> _lazyFlood(MeshMessage message, String fromPeerAddress) async {
    final connectedPeers = getConnectedPeerIds();
    final fromCryptoId = _connectionManager.getCryptoPeerId(fromPeerAddress);
    
    final candidates = connectedPeers.where((peerId) {
      if (peerId == fromCryptoId) return false;
      if (peerId == message.senderPeerId) return false;
      if (_deduplicationCache.hasForwardedTo(message.messageId, peerId)) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await _messageQueue.enqueue(queuedMessage);
      return;
    }

    final rng = Random();
    final maxForward = candidates.length < 3 ? candidates.length : (2 + rng.nextInt(2));
    candidates.shuffle(rng);
    final selected = candidates.take(maxForward).toList();

    for (final peerId in selected) {
      final transportId = _connectionManager.getTransportId(peerId);
      if (transportId == null) continue;

      final sent = await _transportService.sendMessage(transportId, message.toBytes());
      if (sent) {
        _deduplicationCache.markForwardedTo(message.messageId, peerId);
      }
    }
  }

  void _onPeerConnected(Peer peer) async {
    await _routeManager.onPeerConnected(peer);
    _queueDebounceTimer?.cancel();
    _queueDebounceTimer = Timer(const Duration(seconds: 2), () async {
      await _processQueue();
      notifyListeners();
    });
    notifyListeners();
  }

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

  void _startQueueProcessing() {
    _queueProcessingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        await _processQueue();
      } catch (e) {
        debugPrint('Error processing queue: $e');
      }
    });
  }

  Future<void> _processQueue() async {
    final queuedMessages = await _messageQueue.getReadyMessages();
    if (queuedMessages.isEmpty) return;
    
    for (final queuedMessage in queuedMessages) {
      if (queuedMessage.isExpired || queuedMessage.shouldDrop) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        continue;
      }

      final currentNextHop = await _routeManager.getNextHop(queuedMessage.message.recipientPeerId);
      if (currentNextHop == null) continue;

      final transportId = _connectionManager.getTransportId(currentNextHop);
      if (transportId == null) continue;

      final sent = await _transportService.sendMessage(transportId, queuedMessage.message.toBytes());

      if (sent) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _routeManager.markRouteSuccess(queuedMessage.message.recipientPeerId, currentNextHop);
      } else {
        await _messageQueue.updateAttempt(queuedMessage.message.messageId);
        await _routeManager.markRouteFailed(queuedMessage.message.recipientPeerId, currentNextHop);
      }
    }
  }

  void _deliverToApplication(MeshMessage message, String content) async {
    if (message.type == MessageType.data) {
      final chatMessage = ChatMessage(
        id: message.messageId,
        peerId: message.senderPeerId,
        content: content,
        timestamp: message.timestamp,
        isSentByMe: false,
        status: MessageStatus.delivered,
      );
      await _db.insertChatMessage(chatMessage);
      _incomingMessageController.add(chatMessage);
    } else if (message.type == MessageType.readReceipt) {
      if (content.startsWith('READ:')) {
        final ids = content.substring(5).split(',');
        for (final id in ids) {
          await _db.updateMessageStatus(id, MessageStatus.seen);
          _statusUpdateController.add(id);
        }
      }
    }
    notifyListeners();
  }

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

  Future<QueueStats> get queueStatus => _messageQueue.getStats();

  RouteManager get routeManager => _routeManager;
  MessageQueue get messageQueue => _messageQueue;
  MultiTransportService get transportService => _transportService;
  String get localPeerId => _cryptoService.localPeerId;

  List<String> getConnectedPeerIds() => _connectionManager.getConnectedCryptoPeerIds();

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _queueDebounceTimer?.cancel();
    _peerDiscoverySubscription?.cancel();
    _transportMessageSubscription?.cancel();
    _incomingMessageController.close();
    _statusUpdateController.close();
    _transportService.dispose();
    super.dispose();
  }
}

/// Result of a send attempt.
enum SendResult {
  /// Delivered directly to the recipient.
  direct,
  /// Successfully routed through one or more hops.
  routed,
  /// No route found, message queued for later.
  noRoute,
  /// Destination reached but message was queued (e.g. pending handshake).
  queued,
  /// Send failed.
  failed,
}

/// Statistics about the message queue.
// Note: QueueStats is already defined in message_queue.dart and imported.

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

