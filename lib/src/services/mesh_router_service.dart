import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import '../utils/distributed_tracer.dart';
import '../utils/token_bucket.dart';
import 'package:sodium/sodium.dart';
import 'crypto_service.dart';
import 'discovery_service.dart';
import 'db_service.dart';
import '../models/chat_message.dart';
import '../models/mesh_message.dart';
import '../models/chat_payload.dart';
import '../models/communication_mode.dart';
import '../models/queued_message.dart';
import '../models/queued_message_detail.dart';
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
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'connection_manager.dart';
import 'transport_service.dart';
import 'wifi_transport.dart';
import 'bluetooth_transport.dart';
import 'emergency_broadcast_service.dart';

enum SendResult {
  routed,
  queued,
  noRoute,
  failed,
}

class RoutingStats {
  final int messagesSent;
  final int messagesFailed;
  final int totalQueuedMessages;
  final int activePeerCount;
  final int totalRoutes;
  final int localQueuedMessages;
  final int meshQueuedMessages;

  RoutingStats({
    required this.messagesSent,
    required this.messagesFailed,
    required this.totalQueuedMessages,
    required this.activePeerCount,
    required this.totalRoutes,
    required this.localQueuedMessages,
    required this.meshQueuedMessages,
  });
}

class MeshRouterService extends ChangeNotifier {
  final DBService _db;
  final DiscoveryService _discovery;

  final CryptoService _cryptoService;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  final MessageQueue messageQueue;
  final RouteManager routeManager;
  final MessageManager messageManager;
  final MultiTransportService transportService;
  final ConnectionManager _connectionManager;
  final EmergencyBroadcastService _emergencyBroadcastService;

  WiFiTransport? _wifiTransport;

  Timer? _maintenanceTimer;
  Timer? _queueProcessingTimer;
  Timer? _queueDebounceTimer;
  StreamSubscription? _peerDiscoverySubscription;
  StreamSubscription? _transportMessageSubscription;
  StreamSubscription? _routeUpdateSubscription;

  int _messagesSent = 0;
  int _messagesFailed = 0;
  final Map<String, int> _lastQueueDiscoveryAttempt = {};
  static const Duration _queueDiscoveryCooldown = Duration(seconds: 15);

  // Rate limiters per peer
  final Map<String, TokenBucket> _peerRateLimiters = {};

  // Stream for incoming messages — ChatScreen listens to this
  final StreamController<ChatMessage> _incomingMessageController =
      StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get onMessageReceived =>
      _incomingMessageController.stream;

  // Stream for raw mesh messages — FileTransferService listens to this
  final StreamController<MeshMessage> _rawMessageController =
      StreamController<MeshMessage>.broadcast();
  Stream<MeshMessage> get onRawMessageReceived => _rawMessageController.stream;

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
    required this.messageQueue,
    required this.routeManager,
    required this.messageManager,
    required this.transportService,
    required ConnectionManager connectionManager,
    required EmergencyBroadcastService emergencyBroadcastService,
  })  : _db = db,
        _discovery = discovery,
        _cryptoService = cryptoService,
        _deduplicationCache = deduplicationCache,
        _signatureVerifier = signatureVerifier,
        _connectionManager = connectionManager,
        _emergencyBroadcastService = emergencyBroadcastService {
    _connectionManager.onHandshakeComplete = (peerId) async {
      AppLogger.print('Handshake complete for $peerId - processing full queue');
      _scheduleQueueProcessing();
      final syncedCount =
          await _emergencyBroadcastService.syncRecentBroadcastsToPeer(peerId);
      if (syncedCount > 0) {
        AppLogger.print(
            'EmergencyBroadcast: synced $syncedCount recent broadcast(s) to $peerId');
      }
      notifyListeners();
    };

    // Listen to connection manager changes (peer activity updates)
    _connectionManager.addListener(() {
      AppLogger.print('ConnectionManager changed - notifying UI');
      notifyListeners();
    });

    _routeUpdateSubscription = routeManager.onRouteUpdated.listen((_) {
      _scheduleQueueProcessing();
    });
  }

  String get localPeerId => _cryptoService.localPeerId;

  RuntimeProfile? getPeerRuntimeProfile(String peerId) =>
      _connectionManager.getPeerRuntimeProfile(peerId);

  // Update local name for WiFi Direct advertising
  void updateLocalName(String name) {
    _wifiTransport?.setLocalIdentity(_cryptoService.localPeerId, name);
    _connectionManager.setDisplayName(name);
    _broadcastIdentityUpdate(name);
  }

  Future<void> _broadcastIdentityUpdate(String name) async {
    final payload = {'peerId': _cryptoService.localPeerId, 'name': name};
    final bytes = utf8.encode(jsonEncode(payload));

    final message = MeshMessage(
      messageId: 'id_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000)}',
      type: MessageType.identityUpdate,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: 'broadcast', // Broadcast to mesh
      ttl: MessageLimits.ttlMax,
      hopCount: 0,
      priority: MessagePriority.normal,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      encryptedContent: Uint8List.fromList(bytes),
      signature: Uint8List(0),
    );

    // Sign the update to prevent spoofing
    final signature = _cryptoService.signMessage(message.toBytesForSigning());
    final signedMessage = message.copyWithSignature(signature);

    AppLogger.print('Broadcasting identity update: $name');
    await _lazyFlood(signedMessage, 'local');
  }

  // Restart WiFi Direct advertising and discovery
  Future<void> restartWiFiDirect() async {
    AppLogger.print('Restarting WiFi Direct...');
    await _wifiTransport?.restartWiFiDirect();
  }

  Future<void> suspendNearbyConnections() async {
    AppLogger.print('Suspending WiFi Direct/Nearby transport...');
    await _wifiTransport?.suspendNearbyConnections();
  }

  Future<void> resumeNearbyConnections() async {
    AppLogger.print('Resuming WiFi Direct/Nearby transport...');
    await _wifiTransport?.resumeNearbyConnections();
  }

  void setRuntimeProfile(RuntimeProfile profile) {
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
        AppLogger.print('Received handshake from ${transportMsg.fromPeerId}');
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
        await routeManager.addRoute(route);

        if (transportMsg.fromPeerId != cryptoPeerId) {
          await _db.deletePeer(transportMsg.fromPeerId);
        }

        notifyListeners();
        return;
      }

      // Not a handshake, treat as mesh message
      await receiveMessage(transportMsg.data, transportMsg.fromAddress);
    } catch (e) {
      AppLogger.print('Error handling transport message: $e');
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
    transportService.addTransport(wifiTransport);
    _wifiTransport = wifiTransport;

    // Create Bluetooth transport (fallback after WiFi)
    final bluetoothTransport = BluetoothTransport();
    bluetoothTransport.onConnectionEstablished = (transportId) {
      _connectionManager.onConnectionEstablished(transportId);
    };
    bluetoothTransport.onConnectionLost = (transportId) {
      _connectionManager.onConnectionLost(transportId);
    };
    transportService.addTransport(bluetoothTransport);

    await transportService.init();

    // Set up connection manager callback for sending handshakes
    _connectionManager.onSendHandshake = (transportId, data) async {
      await transportService.sendMessage(transportId, data);
    };

    // Listen to transport messages
    _transportMessageSubscription =
        transportService.onMessageReceived.listen((transportMsg) {
      _handleTransportMessage(transportMsg);
    });

    // Listen to peer discovery events
    _peerDiscoverySubscription =
        _discovery.onPeerFound.listen(_onPeerConnected);

    // Start background maintenance tasks
    _startMaintenanceTasks();
    _startQueueProcessing();
  }

  // Get connected peer IDs via transport service
  List<String> getConnectedPeerIds() {
    final transportIds = transportService.getConnectedPeerIds();
    return transportIds
        .map((id) => _connectionManager.getCryptoPeerId(id))
        .whereType<String>()
        .toList();
  }

  // Check if a peer has finished handshake and is ready for secure communication
  bool isPeerSecurelyConnected(String peerId) {
    return _connectionManager.isPeerSecurelyConnected(peerId);
  }

  // Check if we have the public keys for this peer to allow encryption
  Future<bool> hasPeerKeys(String peerId) async {
    final key = await _signatureVerifier.getPeerPublicKey(peerId);
    return key != null;
  }

  // Mesh Network Stats for UI
  Future<RoutingStats> get stats async {
    final routeStats = await routeManager.getStats();
    final allQueued = await messageQueue.getAllQueued();

    // Filter for only "User" messages (Data/File) for the UI counters
    final userMessages = allQueued.where((q) =>
        q.message.type == MessageType.data ||
        q.message.type == MessageType.fileTransfer);

    final localCount =
        userMessages.where((q) => q.origin == QueueOrigin.local).length;
    final meshCount =
        userMessages.where((q) => q.origin == QueueOrigin.mesh).length;

    return RoutingStats(
      messagesSent: _messagesSent,
      messagesFailed: _messagesFailed,
      totalQueuedMessages: localCount + meshCount,
      activePeerCount: getConnectedPeerIds().length,
      totalRoutes: routeStats['total_routes'] ?? 0,
      localQueuedMessages: localCount,
      meshQueuedMessages: meshCount,
    );
  }

  Future<List<mesh_route.Route>> getAllRoutesForStatus() async {
    return await routeManager.getAllRoutes();
  }

  Future<List<QueuedMessageDetail>> getQueuedMessageDetails() async {
    final messages = await messageQueue.getAllQueued();
    final details = <QueuedMessageDetail>[];

    for (final qm in messages) {
      // Hide system/protocol messages from the UI list
      if (qm.message.type != MessageType.data &&
          qm.message.type != MessageType.fileTransfer) {
        continue;
      }
      String? preview;
      if (qm.message.type == MessageType.data) {
        preview = await messageManager.decryptContent(qm.message);
      }

      details.add(QueuedMessageDetail(
        messageId: qm.message.messageId,
        recipientPeerId: qm.message.recipientPeerId,
        nextHopPeerId: qm.nextHopPeerId,
        priority: qm.message.priority,
        queuedTimestamp: qm.queuedTimestamp,
        attemptCount: qm.attemptCount,
        origin: qm.origin,
        contentPreview: preview,
      ));
    }
    return details;
  }

  Future<void> removeQueuedMessage(String messageId) async {
    await messageQueue.dequeue(messageId);
    notifyListeners();
  }

  Future<int> removeQueuedMessagesForPeer(String peerId,
      {QueueOrigin? origin}) async {
    final messages = await messageQueue.getAllQueued();
    var count = 0;
    for (final qm in messages) {
      if (qm.message.recipientPeerId == peerId &&
          (origin == null || qm.origin == origin)) {
        await messageQueue.dequeue(qm.message.messageId);
        count++;
      }
    }
    if (count > 0) notifyListeners();
    return count;
  }

  Future<int> promoteQueuedMessageToMesh(String messageId) async {
    final messages = await messageQueue.getAllQueued();
    for (final qm in messages) {
      if (qm.message.messageId == messageId && qm.origin == QueueOrigin.local) {
        await messageQueue.dequeue(messageId);
        await messageQueue.enqueue(qm.copyWith(origin: QueueOrigin.mesh));
        notifyListeners();
        return 1;
      }
    }
    return 0;
  }

  Future<int> promoteQueuedMessagesForPeerToMesh(String peerId) async {
    final messages = await messageQueue.getAllQueued();
    var count = 0;
    for (final qm in messages) {
      if (qm.message.recipientPeerId == peerId &&
          qm.origin == QueueOrigin.local) {
        await messageQueue.dequeue(qm.message.messageId);
        await messageQueue.enqueue(qm.copyWith(origin: QueueOrigin.mesh));
        count++;
      }
    }
    if (count > 0) notifyListeners();
    return count;
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
      );

      final msgId = messageId ?? messageManager.generateMessageId();
      final spanId = DistributedTracer.generateSpanId();
      DistributedTracer.startSpan('sendMessage',
          traceId: msgId,
          spanId: spanId,
          attributes: {'recipient': recipientPeerId, 'mode': mode.name});

      if (mode == CommunicationMode.emergencyBroadcast) {
        final sent = await _emergencyBroadcastService.broadcastMessage(
          messageId: msgId,
          content: content,
        );
        final result = sent ? SendResult.routed : SendResult.failed;
        _recordSendAttempt(result);
        DistributedTracer.endSpan('sendMessage',
            traceId: msgId, spanId: spanId, attributes: {'result': result.name});
        return result;
      }

      final recipientPublicKey =
          await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) {
        DistributedTracer.endSpan('sendMessage',
            traceId: msgId,
            spanId: spanId,
            attributes: {'result': 'failed_no_key'});
        return SendResult.failed;
      }

      final message = await messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
        messageId: msgId,
      );

      final forwarded = await _forwardMessageViaTransport(message);
      
      // Update database status based on result
      MessageStatus finalStatus;
      switch (forwarded) {
        case SendResult.routed:
          finalStatus = MessageStatus.sent;
          break;
        case SendResult.queued:
          finalStatus = MessageStatus.queued;
          break;
        case SendResult.noRoute:
          finalStatus = MessageStatus.noRoute;
          break;
        case SendResult.failed:
          finalStatus = MessageStatus.failed;
          break;
      }
      
      await _db.updateMessageStatus(
        message.messageId,
        finalStatus,
        clearHopCount: true,
        correlationId: message.messageId,
      );
      
      _statusUpdateController.add(message.messageId);
      _recordSendAttempt(forwarded);
      DistributedTracer.endSpan('sendMessage',
          traceId: msgId,
          spanId: spanId,
          attributes: {'result': forwarded.name});
      notifyListeners();
      return forwarded;
    } catch (e) {
      AppLogger.print('ERROR sending message: $e');
      _recordSendAttempt(SendResult.failed);
      return SendResult.failed;
    }
  }

  /// Send a mesh message with custom arbitrary data and type
  Future<SendResult> sendDataMessage({
    required String recipientPeerId,
    required Uint8List data,
    required MessageType type,
    MessagePriority priority = MessagePriority.normal,
  }) async {
    try {
      final recipientPublicKey =
          await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) return SendResult.failed;

      final message = await messageManager.createDataMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        data: data,
        type: type,
        priority: priority,
      );

      final forwarded = await _forwardMessageViaTransport(message);
      
      MessageStatus finalStatus;
      switch (forwarded) {
        case SendResult.routed:
          finalStatus = MessageStatus.sent;
          break;
        case SendResult.queued:
          finalStatus = MessageStatus.queued;
          break;
        case SendResult.noRoute:
          finalStatus = MessageStatus.noRoute;
          break;
        case SendResult.failed:
          finalStatus = MessageStatus.failed;
          break;
      }
      
      await _db.updateMessageStatus(
        message.messageId,
        finalStatus,
        clearHopCount: true,
        correlationId: message.messageId,
      );
      
      _statusUpdateController.add(message.messageId);
      _recordSendAttempt(forwarded);
      notifyListeners();
      return forwarded;
    } catch (e) {
      AppLogger.print('ERROR sending data message: $e');
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

  QueuedMessage _makeLocalQueueEntry(MeshMessage message, String nextHop) =>
      QueuedMessage(
        message: message,
        nextHopPeerId: nextHop,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.local,
      );

  Future<SendResult> _forwardMessageViaTransport(MeshMessage message) async {
    final nextHopCryptoId =
        await routeManager.getNextHop(message.recipientPeerId);

    if (nextHopCryptoId == null) {
      DistributedTracer.logEvent('Forward: No route found',
          traceId: message.messageId);
      final opportunisticForwards = await _opportunisticForward(message, null);
      await messageQueue.enqueue(
          _makeLocalQueueEntry(message, message.recipientPeerId));
      routeManager.discoverRoute(message.recipientPeerId);
      return opportunisticForwards > 0 ? SendResult.routed : SendResult.noRoute;
    }

    final transportId = _connectionManager.getTransportId(nextHopCryptoId);
    if (transportId == null) {
      DistributedTracer.logEvent('Forward: Next hop offline',
          traceId: message.messageId, attributes: {'nextHop': nextHopCryptoId});
      await messageQueue
          .enqueue(_makeLocalQueueEntry(message, nextHopCryptoId));
      return SendResult.queued;
    }

    DistributedTracer.logEvent('Forward: Sending via transport',
        traceId: message.messageId, attributes: {'transportId': transportId});
    final sent =
        await transportService.sendMessage(transportId, message.toBytes());

    if (sent) {
      DistributedTracer.logEvent('Forward: Sent successfully',
          traceId: message.messageId);
      await routeManager.markRouteSuccess(
          message.recipientPeerId, nextHopCryptoId);
      return SendResult.routed;
    } else {
      DistributedTracer.logEvent('Forward: Send failed',
          traceId: message.messageId);
      await messageQueue
          .enqueue(_makeLocalQueueEntry(message, nextHopCryptoId));
      await routeManager.markRouteFailed(
          message.recipientPeerId, nextHopCryptoId);
      return SendResult.queued;
    }
  }

  Future<void> receiveMessage(
      Uint8List rawMessage, String fromPeerAddress) async {
    try {
      final message = MeshMessage.fromBytes(rawMessage);
      final spanId = DistributedTracer.generateSpanId();
      DistributedTracer.startSpan('receiveMessage',
          traceId: message.messageId,
          spanId: spanId,
          attributes: {'from': fromPeerAddress, 'type': message.type.name});

      // Validate TTL bounds to prevent infinite loops and flood attacks
      if (message.ttl <= 0 ||
          message.ttl > MessageLimits.ttlMax ||
          message.hopCount > MessageLimits.ttlMax) {
        AppLogger.print(
            'Dropping message due to invalid TTL/hopCount: ttl=${message.ttl}, hops=${message.hopCount}');
        DistributedTracer.endSpan('receiveMessage',
            traceId: message.messageId,
            spanId: spanId,
            attributes: {'result': 'dropped_invalid_ttl'});
        return;
      }

      final immediateSenderId =
          _connectionManager.getCryptoPeerId(fromPeerAddress);

      // TokenBucket Rate Limiting
      if (immediateSenderId != null) {
        final bucket = _peerRateLimiters.putIfAbsent(
            immediateSenderId,
            () => TokenBucket(
                capacity: RateLimitConfig.tokenBucketCapacity,
                refillRatePerSecond: RateLimitConfig.tokenBucketRefillRate));
        if (!bucket.tryConsume()) {
          AppLogger.print(
              'Rate limit exceeded for $immediateSenderId, dropping message');
          DistributedTracer.endSpan('receiveMessage',
              traceId: message.messageId,
              spanId: spanId,
              attributes: {'result': 'dropped_rate_limit'});
          return;
        }
      }

      if (message.recipientPeerId == broadcastEmergencyDestination) {
        await _emergencyBroadcastService.handleIncomingBroadcast(
            message, fromPeerAddress);
        notifyListeners();
        DistributedTracer.endSpan('receiveMessage',
            traceId: message.messageId,
            spanId: spanId,
            attributes: {'result': 'emergency_handled'});
        return;
      }

      if (_deduplicationCache.hasSeenFingerprint(
          message.messageId, message.senderPeerId, message.hopCount)) {
        DistributedTracer.endSpan('receiveMessage',
            traceId: message.messageId,
            spanId: spanId,
            attributes: {'result': 'dropped_duplicate'});
        return;
      }
      _deduplicationCache.markFingerprint(
          message.messageId, message.senderPeerId, message.hopCount);

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
        await routeManager.addRoute(learnedRoute);
      }

      if (message.type == MessageType.routeRequest &&
          message.encryptedContent != null) {
        final request = RouteRequest.fromBytes(message.encryptedContent!);
        await routeManager.handleRouteRequest(request, fromPeerAddress);
        DistributedTracer.endSpan('receiveMessage',
            traceId: message.messageId,
            spanId: spanId,
            attributes: {'result': 'route_request_handled'});
        return;
      }
      if (message.type == MessageType.routeResponse &&
          message.encryptedContent != null) {
        final response = RouteResponse.fromBytes(message.encryptedContent!);
        await routeManager.handleRouteResponse(response);
        DistributedTracer.endSpan('receiveMessage',
            traceId: message.messageId,
            spanId: spanId,
            attributes: {'result': 'route_response_handled'});
        return;
      }
      if (message.type == MessageType.identityUpdate &&
          message.encryptedContent != null) {
        if (!await _signatureVerifier.verifyMessageSignature(message)) {
          AppLogger.print(
              'Invalid signature for identityUpdate from ${message.senderPeerId}');
          return;
        }

        try {
          final data = jsonDecode(utf8.decode(message.encryptedContent!));
          final name = data['name'];
          final senderId = message.senderPeerId;
          await _handleIdentityUpdate(senderId, name);
          await _lazyFlood(message.copyForForwarding(), fromPeerAddress);
          DistributedTracer.endSpan('receiveMessage',
              traceId: message.messageId,
              spanId: spanId,
              attributes: {'result': 'identity_update_handled'});
          return;
        } catch (e) {
          AppLogger.print('Error parsing identity update: $e');
        }
      }

      final result =
          await messageManager.processMessage(message, fromPeerAddress);

      if (result == ProcessResult.delivered) {
        DistributedTracer.logEvent('Message Delivered',
            traceId: message.messageId, spanId: spanId);
        // Notify raw message listeners (like FileTransferService)
        _rawMessageController.add(message);

        final content = await messageManager.decryptContent(message);
        if (content != null) {
          _deliverToApplication(message, content);
        }
      } else if (result == ProcessResult.queued) {
        await _lazyFlood(message.copyForForwarding(), fromPeerAddress);
      }

      DistributedTracer.endSpan('receiveMessage',
          traceId: message.messageId,
          spanId: spanId,
          attributes: {'result': result.name});
      notifyListeners();
    } catch (e) {
      AppLogger.print('Error receiving message: $e');
      // No traceId if parsing failed, but handled gracefully
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
      await messageQueue.enqueue(queuedMessage);
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
          await transportService.sendMessage(transportId, message.toBytes());
      if (sent) {
        forwardedCount++;
        _deduplicationCache.markForwardedTo(message.messageId, peerId);
      }
    }
    return forwardedCount;
  }

  void _onPeerConnected(Peer peer) async {
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
        await routeManager.expireStaleRoutes();
        final expiredDroppedIds = await messageQueue.removeExpired();
        if (expiredDroppedIds.isNotEmpty) {
          await _markMessagesFailed(expiredDroppedIds);
        }
        await _deduplicationCache.cleanup();
        await _signatureVerifier.unblockExpiredPeers();
        notifyListeners();
      } catch (e) {
        AppLogger.print('Error in maintenance tasks: $e');
      }
    });
  }

  void _startQueueProcessing() {
    _queueProcessingTimer = Timer.periodic(
        MeshRouterTimerConfig.queueProcessInterval, (timer) async {
      try {
        await _processQueue();
      } catch (e) {
        AppLogger.print('Error processing queue: $e');
      }
    });
  }

  Future<void> _processQueue() async {
    final localQueuedMessages =
        await messageQueue.getReadyMessagesByOrigin(QueueOrigin.local);
    final meshQueuedMessages =
        await messageQueue.getReadyMessagesByOrigin(QueueOrigin.mesh);
    final queuedMessages = <QueuedMessage>[
      ...localQueuedMessages,
      ...meshQueuedMessages,
    ];
    if (queuedMessages.isEmpty) return;
    final discoveryRequested = <String>{};

    for (final queuedMessage in queuedMessages) {
      if (queuedMessage.isExpired || queuedMessage.shouldDrop) {
        await messageQueue.dequeue(queuedMessage.message.messageId);
        await _markMessageFailed(queuedMessage.message.messageId);
        continue;
      }

      final currentNextHop =
          await routeManager.getNextHop(queuedMessage.message.recipientPeerId);
      if (currentNextHop == null) {
        final handedOff = await _tryOpportunisticQueueForward(queuedMessage);
        if (!handedOff) {
          _requestQueueRouteDiscovery(
            queuedMessage.message.recipientPeerId,
            discoveryRequested,
          );
        }
        continue;
      }

      final transportId = _connectionManager.getTransportId(currentNextHop);
      if (transportId == null) {
        final handedOff = await _tryOpportunisticQueueForward(queuedMessage);
        if (!handedOff) {
          _requestQueueRouteDiscovery(
            queuedMessage.message.recipientPeerId,
            discoveryRequested,
          );
        }
        continue;
      }

      final sent = await transportService.sendMessage(
          transportId, queuedMessage.message.toBytes());

      if (sent) {
        final isLocalOutgoingData = queuedMessage.message.type ==
                MessageType.data &&
            queuedMessage.message.senderPeerId == _cryptoService.localPeerId;
        if (isLocalOutgoingData) {
          await _db.updateMessageStatus(
            queuedMessage.message.messageId,
            MessageStatus.routing,
            clearHopCount: true,
            correlationId:
                queuedMessage.message.messageId, // Use messageId as distributed Trace ID
          );
          _statusUpdateController.add(queuedMessage.message.messageId);
        }
        await messageQueue.dequeue(queuedMessage.message.messageId);
        await routeManager.markRouteSuccess(
            queuedMessage.message.recipientPeerId, currentNextHop);
      } else {
        final handedOff = await _tryOpportunisticQueueForward(queuedMessage);
        if (handedOff) {
          await routeManager.markRouteFailed(
              queuedMessage.message.recipientPeerId, currentNextHop);
          continue;
        }
        final dropped =
            await messageQueue.updateAttempt(queuedMessage.message.messageId);
        if (dropped) {
          await _markMessageFailed(queuedMessage.message.messageId);
        }
        await routeManager.markRouteFailed(
            queuedMessage.message.recipientPeerId, currentNextHop);
      }
    }
  }

  void _requestQueueRouteDiscovery(
    String recipientPeerId,
    Set<String> cycleRequested,
  ) {
    if (cycleRequested.contains(recipientPeerId)) return;
    cycleRequested.add(recipientPeerId);

    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAttempt = _lastQueueDiscoveryAttempt[recipientPeerId];
    if (lastAttempt != null &&
        now - lastAttempt < _queueDiscoveryCooldown.inMilliseconds) {
      return;
    }

    _lastQueueDiscoveryAttempt[recipientPeerId] = now;
    routeManager.discoverRoute(recipientPeerId);
  }

  Future<bool> _tryOpportunisticQueueForward(
      QueuedMessage queuedMessage) async {
    if (queuedMessage.origin != QueueOrigin.mesh) {
      return false;
    }

    final forwarded = await _opportunisticForward(queuedMessage.message, null);
    if (forwarded <= 0) {
      return false;
    }

    final isLocalOutgoingData =
        queuedMessage.message.type == MessageType.data &&
            queuedMessage.message.senderPeerId == _cryptoService.localPeerId;
    if (isLocalOutgoingData) {
      await _db.updateMessageStatus(
        queuedMessage.message.messageId,
        MessageStatus.routing,
        clearHopCount: true,
        correlationId: queuedMessage.message.messageId,
      );
      _statusUpdateController.add(queuedMessage.message.messageId);
    }

    await messageQueue.dequeue(queuedMessage.message.messageId);
    return true;
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
      correlationId: messageId,
    );
    _statusUpdateController.add(messageId);
  }

  void _deliverToApplication(MeshMessage message, String content) async {
    if (message.type == MessageType.data) {
      final payload = ChatPayload.decode(content);
      final totalHops = message.hopCount + 1;
      final chatMessage = ChatMessage(
        id: message.messageId,
        peerId: message.senderPeerId,
        content: payload.text,
        timestamp: message.timestamp,
        isSentByMe: false,
        status: MessageStatus.sent,
        hopCount: totalHops,
        replyToMessageId: payload.replyToMessageId,
        replyToContent: payload.replyToContent,
        replyToPeerId: payload.replyToPeerId,
        locationLatitude: payload.location?.latitude,
        locationLongitude: payload.location?.longitude,
        locationAccuracyMeters: payload.location?.accuracyMeters,
        locationTimestamp: payload.location?.timestamp,
      );

      await _db.insertChatMessage(chatMessage);
      _incomingMessageController.add(chatMessage);
    }
  }

  Future<void> _handleIdentityUpdate(String senderId, String name) async {
    final peer = await _db.getPeer(senderId);
    if (peer == null) return;

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return;
    if (peer.displayName == trimmedName) return;

    final oldName = peer.displayName;
    AppLogger.print('Identity update for $senderId: $oldName -> $trimmedName');

    // Update DB
    await _db.updatePeerName(senderId, trimmedName);

    // Refresh UI
    notifyListeners();

    // Add system message to chat
    final systemMsg = ChatMessage(
      id: 'system_${DateTime.now().millisecondsSinceEpoch}_${senderId.hashCode}',
      peerId: senderId,
      content: '$oldName changed their name to $trimmedName',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSentByMe: false,
      status: MessageStatus.sent,
      isRead: true,
      isSystem: true,
    );
    await _db.insertChatMessage(systemMsg);
    _incomingMessageController.add(systemMsg);
  }

  Future<void> shutdown() async {
    dispose();
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _queueDebounceTimer?.cancel();
    _peerDiscoverySubscription?.cancel();
    _transportMessageSubscription?.cancel();
    _routeUpdateSubscription?.cancel();
    _incomingMessageController.close();
    _rawMessageController.close();
    _statusUpdateController.close();
    _wifiDiscoveryFailureController.close();
    super.dispose();
  }
}
