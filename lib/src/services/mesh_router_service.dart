import 'dart:async';
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
    required MessageQueue messageQueue,
    required RouteManager routeManager,
    required MessageManager messageManager,
    required MultiTransportService transportService,
    required ConnectionManager connectionManager,
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
      );

      final msgId = messageId ?? _generateMessageId();
      final spanId = DistributedTracer.generateSpanId();
      DistributedTracer.startSpan('sendMessage', traceId: msgId, spanId: spanId, attributes: {'recipient': recipientPeerId, 'mode': mode.name});

      if (mode == CommunicationMode.emergencyBroadcast) {
        final sent = await _emergencyBroadcastService.broadcastMessage(
          messageId: msgId,
          content: content,
        );
        final result = sent ? SendResult.routed : SendResult.failed;
        _recordSendAttempt(result);
        DistributedTracer.endSpan('sendMessage', traceId: msgId, spanId: spanId, attributes: {'result': result.name});
        return result;
      }

      final recipientPublicKey =
          await _signatureVerifier.getPeerPublicKey(recipientPeerId);
      if (recipientPublicKey == null) {
        DistributedTracer.endSpan('sendMessage', traceId: msgId, spanId: spanId, attributes: {'result': 'failed_no_key'});
        return SendResult.failed;
      }

      final message = await _messageManager.createMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        content: content,
        priority: priority,
        messageId: msgId,
      );

      final forwarded = await _forwardMessageViaTransport(message);
      _recordSendAttempt(forwarded);
      DistributedTracer.endSpan('sendMessage', traceId: msgId, spanId: spanId, attributes: {'result': forwarded.name});
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

      final message = await _messageManager.createDataMessage(
        recipientPeerId: recipientPeerId,
        recipientPublicKey: recipientPublicKey,
        data: data,
        type: type,
        priority: priority,
      );

      final forwarded = await _forwardMessageViaTransport(message);
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

  Future<SendResult> _forwardMessageViaTransport(MeshMessage message) async {
    final nextHopCryptoId =
        await _routeManager.getNextHop(message.recipientPeerId);

    if (nextHopCryptoId == null) {
      DistributedTracer.logEvent('Forward: No route found', traceId: message.messageId);
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
      DistributedTracer.logEvent('Forward: Next hop offline', traceId: message.messageId, attributes: {'nextHop': nextHopCryptoId});
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHopCryptoId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: QueueOrigin.local,
      );
      await _messageQueue.enqueue(queuedMessage);
      return SendResult.queued;
    }

    DistributedTracer.logEvent('Forward: Sending via transport', traceId: message.messageId, attributes: {'transportId': transportId});
    final sent =
        await _transportService.sendMessage(transportId, message.toBytes());

    if (sent) {
      DistributedTracer.logEvent('Forward: Sent successfully', traceId: message.messageId);
      await _routeManager.markRouteSuccess(
          message.recipientPeerId, nextHopCryptoId);
      return SendResult.routed;
    } else {
      DistributedTracer.logEvent('Forward: Send failed', traceId: message.messageId);
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
      final message = MeshMessage.fromBytes(rawMessage);
      final spanId = DistributedTracer.generateSpanId();
      DistributedTracer.startSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'from': fromPeerAddress, 'type': message.type.name});

      // Validate TTL bounds to prevent infinite loops and flood attacks
      if (message.ttl <= 0 || message.ttl > MessageLimits.ttlMax || message.hopCount > MessageLimits.ttlMax) {
        AppLogger.print('Dropping message due to invalid TTL/hopCount: ttl=${message.ttl}, hops=${message.hopCount}');
        DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'dropped_invalid_ttl'});
        return;
      }

      final immediateSenderId = _connectionManager.getCryptoPeerId(fromPeerAddress);

      // TokenBucket Rate Limiting
      if (immediateSenderId != null) {
        final bucket = _peerRateLimiters.putIfAbsent(
            immediateSenderId,
            () => TokenBucket(
                capacity: RateLimitConfig.tokenBucketCapacity,
                refillRatePerSecond: RateLimitConfig.tokenBucketRefillRate));
        if (!bucket.tryConsume()) {
          AppLogger.print('Rate limit exceeded for $immediateSenderId, dropping message');
          DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'dropped_rate_limit'});
          return;
        }
      }

      if (message.recipientPeerId == broadcastEmergencyDestination) {
        await _emergencyBroadcastService.handleIncomingBroadcast(
            message, fromPeerAddress);
        notifyListeners();
        DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'emergency_handled'});
        return;
      }

      if (_deduplicationCache.hasSeenFingerprint(
          message.messageId, message.senderPeerId, message.hopCount)) {
        DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'dropped_duplicate'});
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
        await _routeManager.addRoute(learnedRoute);
      }

      if (message.type == MessageType.routeRequest &&
          message.encryptedContent != null) {
        final request = RouteRequest.fromBytes(message.encryptedContent!);
        await _routeManager.handleRouteRequest(request, fromPeerAddress);
        DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'route_request_handled'});
        return;
      }
      if (message.type == MessageType.routeResponse &&
          message.encryptedContent != null) {
        final response = RouteResponse.fromBytes(message.encryptedContent!);
        await _routeManager.handleRouteResponse(response);
        DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': 'route_response_handled'});
        return;
      }

      final result =
          await _messageManager.processMessage(message, fromPeerAddress);

      if (result == ProcessResult.delivered) {
        DistributedTracer.logEvent('Message Delivered', traceId: message.messageId, spanId: spanId);
        // Notify raw message listeners (like FileTransferService) only if intended for us
        _rawMessageController.add(message);

        final content = await _messageManager.decryptContent(message);
        if (content != null) {
          _deliverToApplication(message, content);
        }
      } else if (result == ProcessResult.queued) {
        await _lazyFlood(message.copyForForwarding(), fromPeerAddress);
      }

      DistributedTracer.endSpan('receiveMessage', traceId: message.messageId, spanId: spanId, attributes: {'result': result.name});
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
        await _messageQueue.getReadyMessagesByOrigin(QueueOrigin.local);
    final meshQueuedMessages =
        await _messageQueue.getReadyMessagesByOrigin(QueueOrigin.mesh);
    final queuedMessages = <QueuedMessage>[
      ...localQueuedMessages,
      ...meshQueuedMessages,
    ];
    if (queuedMessages.isEmpty) return;
    final discoveryRequested = <String>{};

    for (final queuedMessage in queuedMessages) {
      if (queuedMessage.isExpired || queuedMessage.shouldDrop) {
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _markMessageFailed(queuedMessage.message.messageId);
        continue;
      }

      final currentNextHop =
          await _routeManager.getNextHop(queuedMessage.message.recipientPeerId);
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

      final sent = await _transportService.sendMessage(
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
            correlationId: queuedMessage.message.messageId, // Use messageId as distributed Trace ID
          );
          _statusUpdateController.add(queuedMessage.message.messageId);
        }
        await _messageQueue.dequeue(queuedMessage.message.messageId);
        await _routeManager.markRouteSuccess(
            queuedMessage.message.recipientPeerId, currentNextHop);
      } else {
        final handedOff = await _tryOpportunisticQueueForward(queuedMessage);
        if (handedOff) {
          await _routeManager.markRouteFailed(
              queuedMessage.message.recipientPeerId, currentNextHop);
          continue;
        }
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
    _routeManager.discoverRoute(recipientPeerId);
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

    await _messageQueue.dequeue(queuedMessage.message.messageId);
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
        final priorityOrder = a.priority.index.compareTo(b.priority.index);
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

  Future<int> promoteQueuedMessageToMesh(String messageId) async {
    final queued = await _messageQueue.getAllQueued();
    QueuedMessage? target;
    for (final item in queued) {
      if (item.message.messageId == messageId &&
          item.origin == QueueOrigin.local) {
        target = item;
        break;
      }
    }
    if (target == null) return 0;

    final updated = target.copyWith(
      origin: QueueOrigin.mesh,
      attemptCount: 0,
      nextRetryTime: 0,
    );
    await _messageQueue.enqueue(updated);
    _routeManager.discoverRoute(target.message.recipientPeerId);
    _scheduleQueueProcessing();
    notifyListeners();
    return 1;
  }

  Future<int> promoteQueuedMessagesForPeerToMesh(String recipientPeerId) async {
    final queued = await _messageQueue.getAllQueued();
    var moved = 0;
    for (final item in queued) {
      if (item.message.recipientPeerId != recipientPeerId ||
          item.origin != QueueOrigin.local) {
        continue;
      }
      final updated = item.copyWith(
        origin: QueueOrigin.mesh,
        attemptCount: 0,
        nextRetryTime: 0,
      );
      await _messageQueue.enqueue(updated);
      moved++;
    }

    if (moved > 0) {
      _routeManager.discoverRoute(recipientPeerId);
      _scheduleQueueProcessing();
      notifyListeners();
    }
    return moved;
  }

  RouteManager get routeManager => _routeManager;
  MessageQueue get messageQueue => _messageQueue;
  MessageManager get messageManager => _messageManager;
  MultiTransportService get transportService => _transportService;
  String get localPeerId => _cryptoService.localPeerId;

  List<String> getConnectedPeerIds() =>
      _connectionManager.getConnectedCryptoPeerIds();

  RuntimeProfile? getPeerRuntimeProfile(String peerId) =>
      _connectionManager.getPeerRuntimeProfile(peerId);

  Future<void> shutdown() async {
    _maintenanceTimer?.cancel();
    _queueProcessingTimer?.cancel();
    _queueDebounceTimer?.cancel();
    _peerDiscoverySubscription?.cancel();
    _transportMessageSubscription?.cancel();
    _routeUpdateSubscription?.cancel();
    _routeManager.dispose();
    await _incomingMessageController.close();
    await _statusUpdateController.close();
    await _wifiDiscoveryFailureController.close();
    await _rawMessageController.close();
    await _transportService.dispose();
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}

enum SendResult {
  routed,
  noRoute,
  queued,
  failed,
}

class RoutingStats {
  final int totalRoutes;
  final int localQueuedMessages;
  final int meshQueuedMessages;
  final int blockedPeers;
  final int messagesSent;

  final int messagesFailed;
  final int activePeerCount;

  RoutingStats({
    required this.totalRoutes,
    required this.localQueuedMessages,
    required this.meshQueuedMessages,
    required this.blockedPeers,
    required this.messagesSent,

    required this.messagesFailed,
    required this.activePeerCount,
  });

  int get queuedMessages => localQueuedMessages;
  int get totalQueuedMessages => localQueuedMessages + meshQueuedMessages;








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

