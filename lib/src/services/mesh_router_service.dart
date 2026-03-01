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
import '../models/route_discovery.dart';
import '../models/runtime_profile.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import '../config/identity_ui_config.dart';
import '../config/protocol_config.dart';
import 'message_manager.dart';
import 'route_manager.dart';
import 'message_queue.dart';
import 'file_transfer_service.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'connection_manager.dart';
import 'transport_service.dart';
import 'wifi_transport.dart';
import 'bluetooth_transport.dart';
import 'emergency_broadcast_service.dart';
import 'package:uuid/uuid.dart';

class MeshRouterService extends ChangeNotifier {
  final DBService _db;
  final DiscoveryService _discovery;

  final CryptoService _cryptoService;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  final MessageQueue _messageQueue;
  final RouteManager _routeManager;
  final MessageManager _messageManager;
  final MultiTransportService _transportService;
  final ConnectionManager _connectionManager;
  final FileTransferService _fileTransferService;
  final EmergencyBroadcastService _emergencyBroadcastService;

  WiFiTransport? _wifiTransport;

  Timer? _maintenanceTimer;
  Timer? _queueProcessingTimer;
  Timer? _queueDebounceTimer;
  StreamSubscription? _peerDiscoverySubscription;
  StreamSubscription? _transportMessageSubscription;
  StreamSubscription? _routeUpdateSubscription;

  int _messagesSent = 0;
  final int _messagesDelivered = 0;
  int _messagesFailed = 0;
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;

  // Stream for incoming messages — ChatScreen listens to this
  final StreamController<ChatMessage> _incomingMessageController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessageReceived =>
      _incomingMessageController.stream;

  // Stream for message status updates (IDs of changed messages)
  final StreamController<String> _statusUpdateController =
      StreamController<String>.broadcast();
  Stream<String> get onMessageStatusChanged => _statusUpdateController.stream;
  final StreamController<WiFiDiscoveryFailure> _wifiDiscoveryFailureController =
      StreamController<WiFiDiscoveryFailure>.broadcast();
  Stream<WiFiDiscoveryFailure> get onWiFiDiscoveryFailure =>
      _wifiDiscoveryFailureController.stream;

  MeshRouterService({
    required Sodium sodium,
    required DBService db,
    required DiscoveryService discovery,
    required CryptoService cryptoService,
    required DeduplicationCache deduplicationCache,
    required SignatureVerifier signatureVerifier,
    required MessageQueue messageQueue,
    required RouteManager routeManager,
    required MessageManager messageManager,
    required MultiTransportService transportService,
    required ConnectionManager connectionManager,
    required FileTransferService fileTransferService,
    required EmergencyBroadcastService emergencyBroadcastService,
  })  : _db = db,
        _discovery = discovery,
        _cryptoService = cryptoService,
        _deduplicationCache = deduplicationCache,
        _signatureVerifier = signatureVerifier,
        _messageQueue = messageQueue,
        _routeManager = routeManager,
        _messageManager = messageManager,
        _transportService = transportService,
        _connectionManager = connectionManager,
        _fileTransferService = fileTransferService,
        _emergencyBroadcastService = emergencyBroadcastService {
    _connectionManager.onHandshakeComplete = (peerId) async {
      debugPrint('Handshake complete for $peerId - processing full queue');
      _scheduleQueueProcessing();
      _fileTransferService.onPeerReconnected(peerId);
      notifyListeners();
    };

    // Listen to connection manager changes (peer activity updates)
    _connectionManager.addListener(() {
      debugPrint('ConnectionManager changed - notifying UI');
      notifyListeners();
    });

    _routeUpdateSubscription = _routeManager.onRouteUpdated.listen((_) {
      _scheduleQueueProcessing();
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

  void setRuntimeProfile(RuntimeProfile profile) {
    _runtimeProfile = profile;
    _connectionManager.setRuntimeProfile(profile);
    _emergencyBroadcastService.setRuntimeProfile(profile);
  }

  // Handle incoming transport message (could be handshake or mesh message)
  Future<void> _handleTransportMessage(TransportMessage transportMsg) async {
    try {
      // Update peer activity for any received data
      await _connectionManager.updatePeerActivity(transportMsg.fromPeerId);

      if (transportMsg.data.length == ProtocolConfig.keepAlivePacketLength &&
          transportMsg.data[0] == ProtocolConfig.keepAliveByte &&
          transportMsg.data[1] == ProtocolConfig.keepAliveByte) {
        return;
      }

      // Try to parse as handshake first
      final handshake = HandshakeMessage.fromBytes(transportMsg.data);
      if (handshake != null) {
        debugPrint('Received handshake from ${transportMsg.fromPeerId}');
        final wasComplete =
            _connectionManager.isHandshakeComplete(transportMsg.fromPeerId);
        await _connectionManager.handleHandshake(
            transportMsg.fromPeerId, handshake);

        // Ensure reciprocal handshake for peers that sent us one before our
        // connection-established callback fired.
        if (!wasComplete) {
          // Force one reciprocal handshake on first inbound handshake.
          // This covers cases where an earlier outbound handshake was dropped.
          await _connectionManager.sendHandshake(
            transportId: transportMsg.fromPeerId,
            reason: 'reciprocal_after_inbound',
            force: true,
          );
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
    final localId = _cryptoService.localPeerId;
    final shortId = localId.length >= IdentityUiConfig.localNameSuffixLength
        ? localId.substring(0, IdentityUiConfig.localNameSuffixLength)
        : localId;
    final initialName = '${IdentityUiConfig.localDisplayNamePrefix} $shortId';
    _connectionManager.setDisplayName(initialName);

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
    wifiTransport.onDiscoveryFailure = (failure) {
      _wifiDiscoveryFailureController.add(failure);
    };
    wifiTransport.setLocalIdentity(_cryptoService.localPeerId, initialName);
    _transportService.addTransport(wifiTransport);
    _wifiTransport = wifiTransport;

    // Create Bluetooth transport (fallback after WiFi)
    final bluetoothTransport = BluetoothTransport();
    bluetoothTransport.onConnectionEstablished = (transportId) {
      _connectionManager.onConnectionEstablished(transportId);
    };
    bluetoothTransport.onConnectionLost = (transportId) {
      _connectionManager.onConnectionLost(transportId);
    };
    _transportService.addTransport(bluetoothTransport);

    await _transportService.init();

    // Set up connection manager callback for sending handshakes
    _connectionManager.onSendHandshake = (transportId, data) async {
      await _transportService.sendMessage(transportId, data);
    };

    // Listen to transport messages
    _transportMessageSubscription =
        _transportService.onMessageReceived.listen((transportMsg) {
      _handleTransportMessage(transportMsg);
    });

    // Listen to peer discovery events
    _peerDiscoverySubscription =
        _discovery.onPeerFound.listen(_onPeerConnected);

    // Start background maintenance tasks
    _startMaintenanceTasks();
    _startQueueProcessing();
  }

  /// Generate a globally unique, sender-prefixed message ID.
  String _generateMessageId() {
    final localId = _cryptoService.localPeerId;
    final prefix = localId.length >= MessageLimits.generatedIdSenderPrefixLength
        ? localId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
        : localId;
    // MeshMessage wire format currently reserves 36 bytes for messageId.
    // Keep IDs <= 36 chars: "<8-char-prefix>_<27-char-uuid-fragment>"
    final compactUuid = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    return '${prefix}_$compactUuid';
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
      final effectiveMode = (_runtimeProfile != RuntimeProfile.normalDirect &&
              mode == CommunicationMode.direct)
          ? CommunicationMode.mesh
          : mode;

      final msgId = messageId ?? _generateMessageId();
      if (effectiveMode == CommunicationMode.emergencyBroadcast) {
        final sent = await _emergencyBroadcastService.broadcastMessage(
          messageId: msgId,
          content: content,
        );
        final result = sent ? SendResult.routed : SendResult.failed;
        _recordSendAttempt(result);
        return result;
      }

      final recipientPublicKey =
          await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) return SendResult.failed;

      final message = await _messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
        messageId: msgId,
      );

      switch (effectiveMode) {
        case CommunicationMode.direct:
          final result = await _sendDirect(message, recipientPeerId);
          _recordSendAttempt(result);
          notifyListeners();
          return result;
        case CommunicationMode.mesh:
          final forwarded = await _forwardMessageViaTransport(message);
          _recordSendAttempt(forwarded);
          notifyListeners();
          return forwarded;
        case CommunicationMode.emergencyBroadcast:
          _recordSendAttempt(SendResult.failed);
          return SendResult.failed;
      }
    } catch (e) {
      debugPrint('ERROR sending message: $e');
      _recordSendAttempt(SendResult.failed);
      return SendResult.failed;
    }
  }

  void _recordSendAttempt(SendResult result) {
    _messagesSent++;
    if (result == SendResult.failed) {
      _messagesFailed++;
    }
  }

  Future<SendResult> _sendDirect(
      MeshMessage message, String recipientPeerId) async {
    final transportId = _connectionManager.getTransportId(recipientPeerId);
    if (transportId == null) {
      return _forwardMessageViaTransport(message);
    }

    final sent =
        await _transportService.sendMessage(transportId, message.toBytes());

    if (sent) {
      await _routeManager.markRouteSuccess(recipientPeerId, recipientPeerId);
      return SendResult.direct;
    } else {
      return _forwardMessageViaTransport(message);
    }
  }

  Future<SendResult> _forwardMessageViaTransport(MeshMessage message) async {
    final nextHopCryptoId =
        await _routeManager.getNextHop(message.recipientPeerId);

    if (nextHopCryptoId == null) {
      final opportunisticForwards = await _opportunisticForward(message, null);
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.local,
      );
      await _messageQueue.enqueue(queuedMessage);
      _routeManager.discoverRoute(message.recipientPeerId);
      return opportunisticForwards > 0 ? SendResult.routed : SendResult.noRoute;
    }

    final transportId = _connectionManager.getTransportId(nextHopCryptoId);
    if (transportId == null) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.local,
      );
      await _messageQueue.enqueue(queuedMessage);
      return SendResult.queued;
    }

    final sent =
        await _transportService.sendMessage(transportId, message.toBytes());

    if (sent) {
      await _routeManager.markRouteSuccess(
          message.recipientPeerId, nextHopCryptoId);
      return nextHopCryptoId == message.recipientPeerId
          ? SendResult.direct
          : SendResult.routed;
    } else {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.local,
      );
      await _messageQueue.enqueue(queuedMessage);
      await _routeManager.markRouteFailed(
          message.recipientPeerId, nextHopCryptoId);
      return SendResult.queued;
    }
  }

  Future<void> receiveMessage(
      Uint8List rawMessage, String fromPeerAddress) async {
    try {
      if (FileTransferService.isFileTransferMessage(rawMessage)) {
        final cryptoId = _connectionManager.getCryptoPeerId(fromPeerAddress);
        if (cryptoId != null) {
          await _fileTransferService.dispatchRawMessage(cryptoId, rawMessage);
          return;
        }
      }

      final message = MeshMessage.fromBytes(rawMessage);

      if (message.recipientPeerId == broadcastEmergencyDestination) {
        await _emergencyBroadcastService.handleIncomingBroadcast(
            message, fromPeerAddress);
        notifyListeners();
        return;
      }

      if (_deduplicationCache.hasSeenFingerprint(
          message.messageId, message.senderPeerId, message.hopCount)) {
        return;
      }
      _deduplicationCache.markFingerprint(
          message.messageId, message.senderPeerId, message.hopCount);

      final immediateSenderId =
          _connectionManager.getCryptoPeerId(fromPeerAddress);
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

      if (message.type == MessageType.routeRequest &&
          message.encryptedContent != null) {
        final request = RouteRequest.fromBytes(message.encryptedContent!);
        await _routeManager.handleRouteRequest(request, fromPeerAddress);
        return;
      }
      if (message.type == MessageType.routeResponse &&
          message.encryptedContent != null) {
        final response = RouteResponse.fromBytes(message.encryptedContent!);
        await _routeManager.handleRouteResponse(response);
        return;
      }

      final result =
          await _messageManager.processMessage(message, fromPeerAddress);

      if (result == ProcessResult.delivered) {
        final content = await _messageManager.decryptContent(message);
        if (content != null) {
          _deliverToApplication(message, content);
        }
      } else if (result == ProcessResult.queued) {
        await _lazyFlood(message.copyForForwarding(), fromPeerAddress);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error receiving message: $e');
    }
  }

  Future<void> _lazyFlood(MeshMessage message, String fromPeerAddress) async {
    final forwarded = await _opportunisticForward(message, fromPeerAddress);
    if (forwarded == 0) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.mesh,
      );
      await _messageQueue.enqueue(queuedMessage);
    }
  }

  Future<int> _opportunisticForward(
      MeshMessage message, String? fromPeerAddress) async {
    if (message.ttl <= 0) return 0;
    final alreadyForwarded =
        _deduplicationCache.getForwardCount(message.messageId);
    if (alreadyForwarded >= MeshForwardingLimits.opportunisticMaxForwardCount) {
      return 0;
    }

    final connectedPeers = getConnectedPeerIds();
    final fromCryptoId = fromPeerAddress == null
        ? null
        : _connectionManager.getCryptoPeerId(fromPeerAddress);

    final candidates = connectedPeers.where((peerId) {
      if (peerId == fromCryptoId) return false;
      if (peerId == message.senderPeerId) return false;
      if (_deduplicationCache.hasForwardedTo(message.messageId, peerId)) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return 0;

    final rng = Random();
    candidates.shuffle(rng);
    final remainingBudget =
        MeshForwardingLimits.opportunisticMaxForwardCount - alreadyForwarded;
    final fanoutRange = MeshForwardingLimits.opportunisticFanoutMax -
        MeshForwardingLimits.opportunisticFanoutMin +
        1;
    final targetFanout =
        MeshForwardingLimits.opportunisticFanoutMin + rng.nextInt(fanoutRange);
    final desired =
        candidates.length < MeshForwardingLimits.opportunisticFanoutMax
            ? candidates.length
            : targetFanout;
    final maxForward = desired < remainingBudget ? desired : remainingBudget;

    var forwardedCount = 0;
    for (final peerId in candidates.take(maxForward)) {
      final transportId = _connectionManager.getTransportId(peerId);
      if (transportId == null) continue;
      final sent =
          await _transportService.sendMessage(transportId, message.toBytes());
      if (sent) {
        forwardedCount++;
        _deduplicationCache.markForwardedTo(message.messageId, peerId);
      }
    }
    return forwardedCount;
  }

  void _onPeerConnected(Peer peer) async {
    // Discovery events are not authoritative connectivity.
    // Route creation is done at handshake completion with crypto IDs.
    _scheduleQueueProcessing();
    notifyListeners();
  }

  void _scheduleQueueProcessing() {
    _queueDebounceTimer?.cancel();
    _queueDebounceTimer = Timer(MeshRouterTimerConfig.queueDebounce, () async {
      await _processQueue();
      notifyListeners();
    });
  }

  void _startMaintenanceTasks() {
    _maintenanceTimer = Timer.periodic(
        MeshRouterTimerConfig.maintenanceInterval, (timer) async {
      try {
        await _routeManager.expireStaleRoutes();
        final expiredDroppedIds = await _messageQueue.removeExpired();
        if (expiredDroppedIds.isNotEmpty) {
          await _markMessagesFailed(expiredDroppedIds);
        }
        await _deduplicationCache.cleanup();
        await _signatureVerifier.unblockExpiredPeers();
        notifyListeners();
      } catch (e) {
        debugPrint('Error in maintenance tasks: $e');
      }
    });
  }

  void _startQueueProcessing() {
    _queueProcessingTimer = Timer.periodic(
        MeshRouterTimerConfig.queueProcessInterval, (timer) async {
      try {
        await _processQueue();
      } catch (e) {
        debugPrint('Error processing queue: $e');
      }
    });
  }

  Future<void> _processQueue() async {
    final localQueuedMessages =
        await _messageQueue.getReadyMessagesByOrigin(QueueOrigin.local);
    final meshQueuedMessages =
        await _messageQueue.getReadyMessagesByOrigin(QueueOrigin.mesh);
    final queuedMessages = <QueuedMessage>[
      ...localQueuedMessages,
      ...meshQueuedMessages,
    ];
    if (queuedMessages.isEmpty) return;

    for (final queuedMessage in queuedMessages) {
      if (queuedMessage.isExpired || queuedMessage.shouldDrop) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _markMessageFailed(queuedMessage.message.messageId);
        continue;
      }

      final currentNextHop =
          await _routeManager.getNextHop(queuedMessage.message.recipientPeerId);
      if (currentNextHop == null) continue;

      final transportId = _connectionManager.getTransportId(currentNextHop);
      if (transportId == null) continue;

      final sent = await _transportService.sendMessage(
          transportId, queuedMessage.message.toBytes());

      if (sent) {
        final isLocalOutgoingData = queuedMessage.message.type ==
                MessageType.data &&
            queuedMessage.message.senderPeerId == _cryptoService.localPeerId;
        if (isLocalOutgoingData) {
          final isDirectSession =
              _isDirectSessionWithPeer(queuedMessage.message.recipientPeerId);
          final messageStatus = isDirectSession &&
                  currentNextHop == queuedMessage.message.recipientPeerId
              ? MessageStatus.sent
              : MessageStatus.routing;
          await _db.updateMessageStatus(
            queuedMessage.message.messageId,
            messageStatus,
            clearHopCount: true,
          );
          _statusUpdateController.add(queuedMessage.message.messageId);
        }
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _routeManager.markRouteSuccess(
            queuedMessage.message.recipientPeerId, currentNextHop);
      } else {
        final dropped =
            await _messageQueue.updateAttempt(queuedMessage.message.messageId);
        if (dropped) {
          await _markMessageFailed(queuedMessage.message.messageId);
        }
        await _routeManager.markRouteFailed(
            queuedMessage.message.recipientPeerId, currentNextHop);
      }
    }
  }

  Future<void> _markMessagesFailed(Iterable<String> messageIds) async {
    for (final messageId in messageIds) {
      await _markMessageFailed(messageId);
    }
  }

  Future<void> _markMessageFailed(String messageId) async {
    final chatMessage = await _db.getChatMessageById(messageId);
    if (chatMessage == null || !chatMessage.isSentByMe) return;
    if (chatMessage.status == MessageStatus.failed) return;

    await _db.updateMessageStatus(
      messageId,
      MessageStatus.failed,
      clearHopCount: true,
    );
    _statusUpdateController.add(messageId);
  }

  void _deliverToApplication(MeshMessage message, String content) async {
    if (message.type == MessageType.data) {
      final totalHops = message.hopCount + 1;
      final chatMessage = ChatMessage(
        id: message.messageId,
        peerId: message.senderPeerId,
        content: content,
        timestamp: message.timestamp,
        isSentByMe: false,
        status: MessageStatus.sent,
        hopCount: totalHops,
      );
      await _db.insertChatMessage(chatMessage);
      _incomingMessageController.add(chatMessage);
    }
    notifyListeners();
  }

  Future<RoutingStats> get stats async {
    final routeStats = await _routeManager.getStats();
    final queueStats = await _messageQueue.getStats();
    final sigStats = await _signatureVerifier.getStats();

    return RoutingStats(
      totalRoutes: routeStats['total_routes'] ?? 0,
      localQueuedMessages: queueStats.localOriginMessages,
      meshQueuedMessages: queueStats.meshOriginMessages,
      blockedPeers: sigStats['blocked_peers'] ?? 0,
      messagesSent: _messagesSent,
      messagesDelivered: _messagesDelivered,
      messagesFailed: _messagesFailed,
      activePeerCount: getConnectedPeerIds().length,
    );
  }

  Future<QueueStats> get queueStatus => _messageQueue.getStats();

  Future<List<mesh_route.Route>> getAllRoutesForStatus() async {
    return _routeManager.getAllRoutes();
  }

  Future<List<QueuedMessageDetail>> getQueuedMessageDetails() async {
    final queued = await _messageQueue.getAllQueued();
    if (queued.isEmpty) return [];

    final messageIds = queued.map((q) => q.message.messageId).toSet().toList();
    final chatMessages = await _db.getChatMessagesByIds(messageIds);

    final details = queued.map((q) {
      final chat = chatMessages[q.message.messageId];
      return QueuedMessageDetail(
        messageId: q.message.messageId,
        recipientPeerId: q.message.recipientPeerId,
        nextHopPeerId: q.nextHopPeerId,
        queuedTimestamp: q.queuedTimestamp,
        origin: q.origin,
        attemptCount: q.attemptCount,
        priority: q.message.priority,
        contentPreview: chat?.content,
      );
    }).toList()
      ..sort((a, b) {
        final priorityOrder = b.priority.index.compareTo(a.priority.index);
        if (priorityOrder != 0) return priorityOrder;
        return a.queuedTimestamp.compareTo(b.queuedTimestamp);
      });

    return details;
  }

  Future<int> removeQueuedMessage(String messageId) async {
    await _messageQueue.dequeue(messageId);
    notifyListeners();
    return 1;
  }

  Future<int> removeQueuedMessagesForPeer(
    String recipientPeerId, {
    QueueOrigin? origin,
  }) async {
    final queued = await _messageQueue.getAllQueued();
    final ids = queued
        .where((q) =>
            q.message.recipientPeerId == recipientPeerId &&
            (origin == null || q.origin == origin))
        .map((q) => q.message.messageId)
        .toList();
    for (final id in ids) {
      await _messageQueue.dequeue(id);
    }
    notifyListeners();
    return ids.length;
  }

  RouteManager get routeManager => _routeManager;
  MessageQueue get messageQueue => _messageQueue;
  MultiTransportService get transportService => _transportService;
  FileTransferService get fileTransferService => _fileTransferService;
  String get localPeerId => _cryptoService.localPeerId;

  List<String> getConnectedPeerIds() =>
      _connectionManager.getConnectedCryptoPeerIds();

  RuntimeProfile? getPeerRuntimeProfile(String peerId) =>
      _connectionManager.getPeerRuntimeProfile(peerId);

  bool peerSupportsFileTransfer(String peerId, {bool defaultValue = false}) =>
      _connectionManager.peerSupportsFileTransfer(
        peerId,
        defaultValue: defaultValue,
      );

  bool _isDirectSessionWithPeer(String peerId) {
    final remoteProfile = _connectionManager.getPeerRuntimeProfile(peerId);
    return _runtimeProfile == RuntimeProfile.normalDirect &&
        remoteProfile == RuntimeProfile.normalDirect &&
        _connectionManager.getConnectedCryptoPeerIds().contains(peerId);
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _queueDebounceTimer?.cancel();
    _peerDiscoverySubscription?.cancel();
    _transportMessageSubscription?.cancel();
    _routeUpdateSubscription?.cancel();
    _routeManager.dispose();
    _incomingMessageController.close();
    _statusUpdateController.close();
    _wifiDiscoveryFailureController.close();
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
  final int localQueuedMessages;
  final int meshQueuedMessages;
  final int blockedPeers;
  final int messagesSent;
  final int messagesDelivered;
  final int messagesFailed;
  final int activePeerCount;

  RoutingStats({
    required this.totalRoutes,
    required this.localQueuedMessages,
    required this.meshQueuedMessages,
    required this.blockedPeers,
    required this.messagesSent,
    required this.messagesDelivered,
    required this.messagesFailed,
    required this.activePeerCount,
  });

  // Backward compatibility: "Queued" now represents local-origin queue only.
  int get queuedMessages => localQueuedMessages;
  int get totalQueuedMessages => localQueuedMessages + meshQueuedMessages;

  double get deliverySuccessRate {
    if (messagesSent <= 0) return 1.0;
    final rate = messagesDelivered / messagesSent;
    if (rate < 0) return 0.0;
    if (rate > 1) return 1.0;
    return rate;
  }
}

class QueuedMessageDetail {
  final String messageId;
  final String recipientPeerId;
  final String nextHopPeerId;
  final int queuedTimestamp;
  final QueueOrigin origin;
  final int attemptCount;
  final MessagePriority priority;
  final String? contentPreview;

  QueuedMessageDetail({
    required this.messageId,
    required this.recipientPeerId,
    required this.nextHopPeerId,
    required this.queuedTimestamp,
    required this.origin,
    required this.attemptCount,
    required this.priority,
    this.contentPreview,
  });
}
