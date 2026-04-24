import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/timer_config.dart';
import '../config/identity_ui_config.dart';
import '../config/protocol_config.dart';
import '../config/limits_config.dart';
import 'transport_service.dart';
import 'db_service.dart';

class WiFiTransport implements TransportService {
  final Nearby _nearby = Nearby();
  final StreamController<TransportMessage> _messageController =
      StreamController.broadcast();
  final StreamController<FileTransferProgressEvent> _fileProgressController =
      StreamController.broadcast();
  final Map<String, String> _connectedPeers = {}; // endpointId -> peerId
  
  // Mapping of Nearby Payload IDs to our internal File IDs and source endpoints
  final Map<int, String> _nearbyIdToFileId = {};
  final Map<int, String> _nearbyIdToEndpointId = {};
  
  // Mapping of Nearby Payload IDs to their local file paths
  final Map<int, String> _nearbyIdToLocalPath = {};
  
  final Function(String peerId, String address)? onPeerDiscovered;
  final DBService _db = DBService();

  // Callback for when connection is established
  Function(String transportId)? onConnectionEstablished;

  // Callback for when connection is lost
  Function(String transportId)? onConnectionLost;

  // Callback for discovery failures that require user action.
  Function(WiFiDiscoveryFailure failure)? onDiscoveryFailure;

  @override
  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  @override
  Stream<FileTransferProgressEvent> get onFileProgress => _fileProgressController.stream;

  // Keepalive and Health mechanism
  Timer? _keepaliveTimer;
  Timer? _healthCheckTimer;
  Timer? _reconnectCheckTimer;
  static final Uint8List keepAlivePacket =
      Uint8List.fromList(ProtocolConfig.keepAlivePacket);

  // Track last activity per connection
  final Map<String, int> _lastActivity = {}; // endpointId -> timestamp

  // Track previously connected peers for auto-reconnection (loaded from DB)
  Set<String> _knownPeers =
      {}; // endpointIds we've successfully connected to before
  final Map<String, int> _lastReconnectAttempt = {}; // endpointId -> timestamp

  String? _localName;
  bool _isAdvertising = false;
  bool _isDiscovering = false;
  final Set<String> _pendingConnectionAttempts = {};
  final Map<String, int> _pendingAttemptStartedAt = {};
  final Map<String, int> _lastConnectionAttempt = {};
  final Map<String, Timer> _waitForInitiatorTimers = {};
  final Map<String, Timer> _quickRetryTimers = {};
  final Map<String, int> _quickRetryCounts = {};
  final Map<String, String> _endpointNamesById = {};
  int _lastDiscoveryRefreshTimestamp = 0;
  int _lastEndpointFoundTimestamp = 0;
  int _lastDiscoveryFailureNoticeAt = 0;
  bool _nearbySuspended = false;
  final Queue<_OutboundFrame> _controlSendQueue = Queue<_OutboundFrame>();
  final Queue<_OutboundFrame> _bulkSendQueue = Queue<_OutboundFrame>();
  bool _outboundPumpActive = false;

  WiFiTransport({this.onPeerDiscovered});

  Future<void> suspendNearbyConnections() async {
    if (_nearbySuspended) return;
    _nearbySuspended = true;
    AppLogger.print('WiFiTransport: suspending Nearby advertising/discovery');

    _pendingConnectionAttempts.clear();
    _pendingAttemptStartedAt.clear();
    _lastConnectionAttempt.clear();
    for (final timer in _waitForInitiatorTimers.values) {
      timer.cancel();
    }
    _waitForInitiatorTimers.clear();
    for (final timer in _quickRetryTimers.values) {
      timer.cancel();
    }
    _quickRetryTimers.clear();
    _quickRetryCounts.clear();
    _endpointNamesById.clear();
    _clearQueuedFrames();

    if (_isAdvertising) {
      try {
        await _nearby.stopAdvertising();
      } catch (e) {
        AppLogger.print('WiFiTransport: failed stopping advertising: $e');
      }
      _isAdvertising = false;
    }

    if (_isDiscovering) {
      try {
        await _nearby.stopDiscovery();
      } catch (e) {
        AppLogger.print('WiFiTransport: failed stopping discovery: $e');
      }
      _isDiscovering = false;
    }

    try {
      await _nearby.stopAllEndpoints();
    } catch (e) {
      AppLogger.print('WiFiTransport: failed disconnecting endpoints: $e');
    }

    _connectedPeers.clear();
    _lastActivity.clear();
  }

  Future<void> resumeNearbyConnections() async {
    if (!_nearbySuspended) return;
    _nearbySuspended = false;
    AppLogger.print('WiFiTransport: resuming Nearby advertising/discovery');
    await restartWiFiDirect();
  }

  @override
  Future<void> init() async {
    try {
      // Load known peers from database
      _knownPeers = await _db.getKnownWiFiEndpoints();
      AppLogger.print(
          'Loaded ${_knownPeers.length} known WiFi Direct endpoints from database');

      // Request necessary permissions
      await _requestPermissions();

      // Start advertising and discovering
      await _startAdvertising();
      await _startDiscovery();

      // Start keepalive timer
      _startKeepalive();

      // Start health check timer
      _startHealthCheck();

      // Start reconnection check timer
      _startReconnectionCheck();
    } catch (e) {
      AppLogger.print('Error initializing WiFi Direct: $e');
    }
  }

  void _startReconnectionCheck() {
    _reconnectCheckTimer?.cancel();
    // Periodically check reconnect state and refresh discovery if needed.
    _reconnectCheckTimer = Timer.periodic(WiFiTimerConfig.reconnectCheckInterval, (timer) async {
      if (_nearbySuspended) {
        return;
      }
      AppLogger.print('=== RECONNECTION CHECK ===');
      AppLogger.print('Known peers: ${_knownPeers.length}');
      AppLogger.print('Connected peers: ${_connectedPeers.length}');
      _cleanupStalePendingAttempts();

      // Reset reconnect attempts for peers that have been disconnected for a while
      final now = DateTime.now().millisecondsSinceEpoch;
      final resetThreshold =
          WiFiTimerConfig.reconnectAttemptResetThreshold.inMilliseconds;

      for (final endpointId in _knownPeers) {
        if (!_connectedPeers.containsKey(endpointId)) {
          final lastAttempt = _lastReconnectAttempt[endpointId];
          if (lastAttempt != null && (now - lastAttempt) > resetThreshold) {
            final oldAttempts = await _db.getReconnectAttempts(endpointId);
            if (oldAttempts > 0) {
              AppLogger.print(
                  'Resetting reconnect attempts for $endpointId (was $oldAttempts)');
              await _db.resetReconnectAttempts(endpointId);
            }
          }
        }
      }

      // If we previously had peers but now have none, proactively refresh discovery
      // to shorten reconnect latency after abrupt app restarts.
      if (_knownPeers.isNotEmpty && _connectedPeers.isEmpty) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final hasRecentEndpointActivity = _lastEndpointFoundTimestamp > 0 &&
            (nowMs - _lastEndpointFoundTimestamp) <
                WiFiTimerConfig
                    .endpointDiscoveryIdleBeforeRestart.inMilliseconds;
        final hasPendingAttempts = _pendingConnectionAttempts.isNotEmpty;
        final elapsed = nowMs - _lastDiscoveryRefreshTimestamp;
        if (!hasPendingAttempts &&
            !hasRecentEndpointActivity &&
            elapsed > WiFiTimerConfig.discoveryRefreshCooldown.inMilliseconds) {
          _lastDiscoveryRefreshTimestamp = nowMs;
          AppLogger.print('No active peers. Proactively refreshing WiFi Direct...');
          await restartWiFiDirect();
        }
      }

      AppLogger.print('=== END RECONNECTION CHECK ===');
    });
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(WiFiTimerConfig.keepAliveInterval, (timer) {
      if (_nearbySuspended) {
        return;
      }
      _sendKeepalives();
    });
    AppLogger.print(
        'WiFi Direct keepalive started (every ${WiFiTimerConfig.keepAliveInterval.inSeconds}s)');
  }

  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(WiFiTimerConfig.healthCheckInterval, (timer) {
      if (_nearbySuspended) {
        return;
      }
      _checkConnectionHealth();
    });
    AppLogger.print('WiFi Direct health check started');
  }

  void _checkConnectionHealth() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeoutMs = WiFiTimerConfig.connectionTimeout.inMilliseconds;
    final staleConnections = <String>[];
    final orphanedActivity = <String>[];

    AppLogger.print('=== CONNECTION HEALTH CHECK ===');
    AppLogger.print('Connected peers: ${_connectedPeers.length}');

    // Check for stale connections
    for (final entry in _lastActivity.entries) {
      // Check if this activity entry has a corresponding connected peer
      if (!_connectedPeers.containsKey(entry.key)) {
        AppLogger.print('  ${entry.key}: ORPHANED (no connection)');
        orphanedActivity.add(entry.key);
        continue;
      }

      final timeSinceActivity = now - entry.value;
      final secondsSinceActivity = (timeSinceActivity / 1000).round();
      AppLogger.print(
          '  ${entry.key}: ${secondsSinceActivity}s since last activity');

      if (timeSinceActivity > timeoutMs) {
        AppLogger.print(
            '  ⚠️ TIMEOUT: ${entry.key} (${secondsSinceActivity}s > ${WiFiTimerConfig.connectionTimeout.inSeconds}s)');
        staleConnections.add(entry.key);
      }
    }

    // Cleanup stale connections
    for (final endpointId in staleConnections) {
      _onDisconnected(endpointId);
      _nearby.disconnectFromEndpoint(endpointId);
    }

    // Cleanup orphaned activity entries
    for (final endpointId in orphanedActivity) {
      _lastActivity.remove(endpointId);
    }
    AppLogger.print('=== END CONNECTION HEALTH CHECK ===');
  }

  void _sendKeepalives() {
    for (final endpointId in _connectedPeers.keys) {
      _nearby.sendBytesPayload(endpointId, keepAlivePacket);
    }
  }

  void _updateActivity(String endpointId) {
    _lastActivity[endpointId] = DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> restartWiFiDirect() async {
    try {
      AppLogger.print('Restarting WiFi Direct advertising and discovery...');

      // Stop current
      if (_isAdvertising) {
        await _nearby.stopAdvertising();
        _isAdvertising = false;
      }
      if (_isDiscovering) {
        await _nearby.stopDiscovery();
        _isDiscovering = false;
      }

      // Wait a moment for stack to settle
      await Future.delayed(WiFiTimerConfig.restartDelay);

      // Start again
      await _startAdvertising();
      await _startDiscovery();
      _lastEndpointFoundTimestamp = DateTime.now().millisecondsSinceEpoch;

      AppLogger.print('WiFi Direct restarted successfully');
    } catch (e) {
      AppLogger.print('Error restarting WiFi Direct: $e');
    }
  }

  Future<void> _restartAdvertising() async {
    try {
      // Stop current advertising
      await _nearby.stopAdvertising();
      _isAdvertising = false;

      // Wait a moment
      await Future.delayed(WiFiTimerConfig.restartDelay);

      // Start with new name
      await _startAdvertising();
    } catch (e) {
      AppLogger.print('Error restarting WiFi Direct advertising: $e');
    }
  }

  Future<void> _requestPermissions() async {
    // Request location permissions explicitly
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      AppLogger.print('Location permission not granted, requesting again...');
      await Permission.location.request();
    }

    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
    ].request();

    final hasLocationPermission =
        await Permission.locationWhenInUse.isGranted ||
            await Permission.location.isGranted;
    if (!hasLocationPermission) {
      _emitDiscoveryFailure(
        const WiFiDiscoveryFailure(
          code: WiFiDiscoveryFailureCode.locationPermissionMissing,
          details: 'Location permission denied',
        ),
      );
    }

    AppLogger.print('Permissions requested');
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising || _nearbySuspended) return;

    try {
      final strategy = Strategy.P2P_CLUSTER;
      final userName = _localName ?? IdentityUiConfig.defaultDisplayName;

      await _nearby.startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      _isAdvertising = true;
      AppLogger.print('WiFi Direct advertising started as: $userName');
    } catch (e) {
      AppLogger.print('Error starting WiFi Direct advertising: $e');
    }
  }

  Future<void> _startDiscovery() async {
    if (_nearbySuspended) return;
    if (_isDiscovering) return;

    try {
      final strategy = Strategy.P2P_CLUSTER;
      final userName = _localName ?? IdentityUiConfig.defaultDisplayName;

      await _nearby.startDiscovery(
        userName,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );

      _isDiscovering = true;
      AppLogger.print('WiFi Direct discovery started');
    } catch (e) {
      AppLogger.print('Error starting WiFi Direct discovery: $e');
      final failure = WiFiDiscoveryFailure.fromError(e.toString());
      if (failure != null) {
        _emitDiscoveryFailure(failure);
      }
    }
  }

  void _emitDiscoveryFailure(WiFiDiscoveryFailure failure) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDiscoveryFailureNoticeAt <
        WiFiTimerConfig.discoveryFailureNoticeCooldown.inMilliseconds) {
      return;
    }
    _lastDiscoveryFailureNoticeAt = now;
    onDiscoveryFailure?.call(failure);
  }

  void _cleanupStalePendingAttempts() {
    if (_pendingConnectionAttempts.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <String>[];
    for (final endpointId in _pendingConnectionAttempts) {
      final startedAt = _pendingAttemptStartedAt[endpointId];
      if (startedAt == null) {
        stale.add(endpointId);
        continue;
      }
      if (now - startedAt >
          WiFiTimerConfig.pendingAttemptTimeout.inMilliseconds) {
        stale.add(endpointId);
      }
    }
    for (final endpointId in stale) {
      AppLogger.print('Clearing stale pending WiFi connection attempt: $endpointId');
      _pendingConnectionAttempts.remove(endpointId);
      _pendingAttemptStartedAt.remove(endpointId);
    }
  }

  bool _shouldWaitForRemoteInitiator(String endpointName) {
    if (_localName == null ||
        _localName!.isEmpty ||
        endpointName.isEmpty ||
        _localName == endpointName) {
      return false;
    }
    // Deterministic tie-break to reduce simultaneous requestConnection collisions.
    // Lexicographically lower name initiates, higher name waits and accepts.
    return (_localName ?? '').compareTo(endpointName) > 0;
  }

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) async {
    if (_nearbySuspended) {
      return;
    }
    AppLogger.print('WiFi Direct endpoint found: $endpointId ($endpointName)');
    _cleanupStalePendingAttempts();
    _lastEndpointFoundTimestamp = DateTime.now().millisecondsSinceEpoch;
    _endpointNamesById[endpointId] = endpointName;

    // Notify discovery service about the peer
    onPeerDiscovered?.call(endpointId, endpointName);

    // Skip if already connected or currently trying.
    if (_connectedPeers.containsKey(endpointId)) {
      AppLogger.print(
          'Already connected to $endpointId, skipping connection request');
      _cancelWaitForInitiator(endpointId);
      return;
    }
    if (_pendingConnectionAttempts.contains(endpointId)) {
      AppLogger.print('Connection attempt already in progress for $endpointId');
      return;
    }
    if (_connectedPeers.length >= TransportLimits.maxConnectedWiFiPeers) {
      AppLogger.print(
          'WiFiTransport: connection cap reached (${TransportLimits.maxConnectedWiFiPeers}), skipping $endpointId');
      return;
    }
    if (_pendingConnectionAttempts.length >=
        TransportLimits.maxPendingWiFiConnections) {
      _scheduleQuickRetry(
        endpointId,
        endpointName: endpointName,
        reason: 'pending_connection_budget_exhausted',
      );
      return;
    }

    if (_shouldWaitForRemoteInitiator(endpointName)) {
      if (!_waitForInitiatorTimers.containsKey(endpointId)) {
        AppLogger.print(
            'Waiting for remote initiator for $endpointId to avoid collision');
        _waitForInitiatorTimers[endpointId] =
            Timer(WiFiTimerConfig.initiatorWaitTimeout, () async {
          _waitForInitiatorTimers.remove(endpointId);
          if (_connectedPeers.containsKey(endpointId) ||
              _pendingConnectionAttempts.contains(endpointId)) {
            return;
          }
          AppLogger.print(
              'Remote initiator wait timed out for $endpointId, self-initiating');
          await _attemptConnection(endpointId, endpointName);
        });
      }
      return;
    }
    _cancelWaitForInitiator(endpointId);
    await _attemptConnection(endpointId, endpointName);
  }

  void _cancelWaitForInitiator(String endpointId) {
    final timer = _waitForInitiatorTimers.remove(endpointId);
    timer?.cancel();
  }

  void _clearQuickRetryState(String endpointId) {
    final timer = _quickRetryTimers.remove(endpointId);
    timer?.cancel();
    _quickRetryCounts.remove(endpointId);
  }

  void _scheduleQuickRetry(String endpointId,
      {String? endpointName, required String reason}) {
    if (_quickRetryTimers.containsKey(endpointId)) return;

    final attempts = _quickRetryCounts[endpointId] ?? 0;
    if (attempts >= WiFiTimerConfig.maxQuickRetries) {
      AppLogger.print('Max quick retries reached for $endpointId');
      return;
    }

    _quickRetryCounts[endpointId] = attempts + 1;
    final delay = WiFiTimerConfig.quickRetryDelay * (attempts + 1);
    AppLogger.print(
        'Scheduling quick retry for $endpointId in ${delay.inSeconds}s (reason: $reason)');

    _quickRetryTimers[endpointId] = Timer(delay, () async {
      _quickRetryTimers.remove(endpointId);
      if (_connectedPeers.containsKey(endpointId) ||
          _pendingConnectionAttempts.contains(endpointId)) {
        return;
      }

      final name = endpointName ?? _endpointNamesById[endpointId];
      if (name != null) {
        await _attemptConnection(endpointId, name);
      }
    });
  }

  Future<void> _attemptConnection(String endpointId, String endpointName) async {
    if (_nearbySuspended) return;

    _pendingConnectionAttempts.add(endpointId);
    _pendingAttemptStartedAt[endpointId] = DateTime.now().millisecondsSinceEpoch;
    _lastConnectionAttempt[endpointId] = DateTime.now().millisecondsSinceEpoch;

    AppLogger.print('Requesting WiFi Direct connection: $endpointId');
    try {
      await _nearby.requestConnection(
        _localName ?? IdentityUiConfig.defaultDisplayName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      AppLogger.print('WiFi Direct requestConnection failed for $endpointId: $e');
      _pendingConnectionAttempts.remove(endpointId);
      _pendingAttemptStartedAt.remove(endpointId);
      _scheduleQuickRetry(endpointId,
          endpointName: endpointName, reason: 'request_connection_exception');
    }
  }

  void _onEndpointLost(String? endpointId) {
    AppLogger.print('WiFi Direct endpoint lost: $endpointId');
    if (endpointId != null) {
      _pendingConnectionAttempts.remove(endpointId);
      _pendingAttemptStartedAt.remove(endpointId);
      _cancelWaitForInitiator(endpointId);
      _clearQuickRetryState(endpointId);
      _endpointNamesById.remove(endpointId);
      _dropQueuedFramesForEndpoint(endpointId);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) async {
    AppLogger.print('WiFi Direct connection initiated: $endpointId');

    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (endpointId, payload) {
          _handleIncomingPayload(endpointId, payload);
        },
        onPayloadTransferUpdate: (endpointId, update) {
          _handleNativeProgress(endpointId, update);
        },
      );
    } catch (e) {
      AppLogger.print('WiFi Direct acceptConnection failed for $endpointId: $e');
    }
  }

  void _onConnectionResult(String endpointId, Status status) async {
    _pendingConnectionAttempts.remove(endpointId);
    _pendingAttemptStartedAt.remove(endpointId);
    _cancelWaitForInitiator(endpointId);
    if (status == Status.CONNECTED) {
      AppLogger.print('WiFi Direct connected: $endpointId');
      _connectedPeers[endpointId] = endpointId;
      _updateActivity(endpointId);
      _knownPeers.add(endpointId);
      await _db.saveKnownWiFiEndpoint(endpointId);
      await _db.resetReconnectAttempts(endpointId);
      onConnectionEstablished?.call(endpointId);
      _clearQuickRetryState(endpointId);
    } else {
      AppLogger.print('WiFi Direct connection failed: $endpointId (status: $status)');
      _connectedPeers.remove(endpointId);
      _lastActivity.remove(endpointId);
      if (_knownPeers.contains(endpointId)) {
        await _db.incrementReconnectAttempts(endpointId);
      }
      _scheduleQuickRetry(endpointId, reason: 'on_connection_result_$status');
    }
  }

  void _onDisconnected(String endpointId) async {
    AppLogger.print('WiFi Direct disconnected: $endpointId');
    _connectedPeers.remove(endpointId);
    _lastActivity.remove(endpointId);
    _dropQueuedFramesForEndpoint(endpointId);
    
    // Only clear mappings for this specific endpoint
    _nearbyIdToEndpointId.removeWhere((pId, eId) {
      if (eId == endpointId) {
        _nearbyIdToFileId.remove(pId);
        _nearbyIdToLocalPath.remove(pId);
        return true;
      }
      return false;
    });
    if (_knownPeers.contains(endpointId)) {
      await _db.resetReconnectAttempts(endpointId);
    }
    onConnectionLost?.call(endpointId);
  }

  void _handleIncomingPayload(String endpointId, Payload payload) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final bytes = Uint8List.fromList(payload.bytes!);

        // Check for File Transfer Mapping Header
        final text = utf8.decode(bytes, allowMalformed: true);
        if (text.startsWith('FT_MAP:')) {
          final parts = text.split(':');
          if (parts.length == 3) {
            final nearbyId = int.tryParse(parts[1]);
            final fileId = parts[2];
            if (nearbyId != null) {
              _nearbyIdToFileId[nearbyId] = fileId;
              _nearbyIdToEndpointId[nearbyId] = endpointId;
              AppLogger.print('Mapped Nearby ID $nearbyId to File ID $fileId for endpoint $endpointId');
              return;
            }
          }
        }

        // Check for keepalive
        if (bytes.length == ProtocolConfig.keepAlivePacketLength &&
            bytes[0] == ProtocolConfig.keepAliveByte &&
            bytes[1] == ProtocolConfig.keepAliveByte) {
          _updateActivity(endpointId);
          return;
        }

        _updateActivity(endpointId);
        _messageController.add(TransportMessage(
          fromPeerId: endpointId,
          fromAddress: endpointId,
          data: bytes,
        ));
      } else if (payload.type == PayloadType.FILE) {
        // Mapping should already exist from the header
        final fileId = _nearbyIdToFileId[payload.id];
        
        // Store the URI for completion
        if (payload.uri != null) {
          _nearbyIdToLocalPath[payload.id] = payload.uri!;
          AppLogger.print('Received file URI for payload ${payload.id}: ${payload.uri}');
        }
        
        if (fileId != null) {
          AppLogger.print('Receiving file payload ${payload.id} for $fileId');
        } else {
          AppLogger.print('Receiving unknown file payload ${payload.id}');
        }
      }
    } catch (e) {
      AppLogger.print('Error handling WiFi Direct payload: $e');
    }
  }

  void _handleNativeProgress(String endpointId, PayloadTransferUpdate update) async {
    final fileId = _nearbyIdToFileId[update.id];
    if (fileId == null) return;

    final progress = update.bytesTransferred / update.totalBytes;
    final isCompleted = update.status == PayloadStatus.SUCCESS;
    final localPath = isCompleted ? _nearbyIdToLocalPath[update.id] : null;

    _fileProgressController.add(FileTransferProgressEvent(
      peerId: endpointId,
      fileId: fileId,
      progress: progress,
      isCompleted: isCompleted,
      localPath: localPath,
    ));
    
    if (isCompleted || update.status == PayloadStatus.FAILURE || update.status == PayloadStatus.CANCELED) {
      _nearbyIdToFileId.remove(update.id);
      _nearbyIdToLocalPath.remove(update.id);
    }
  }

  @override
  Future<bool> sendMessage(String peerId, Uint8List data, {bool isControl = false}) async {
    String? endpointId;
    for (final entry in _connectedPeers.entries) {
      if (entry.value == peerId || entry.key == peerId) {
        endpointId = entry.key;
        break;
      }
    }
    if (endpointId == null) return false;

    return await _enqueuePayload(
      endpointId: endpointId,
      data: data,
      isControl: isControl,
    );
  }

  @override
  Future<bool> sendFile(String peerId, String filePath, String fileId) async {
    String? endpointId;
    for (final entry in _connectedPeers.entries) {
      if (entry.value == peerId || entry.key == peerId) {
        endpointId = entry.key;
        break;
      }
    }
    if (endpointId == null) return false;

    try {
      // In nearby_connections 4.x, we use sendFilePayload directly
      final int nearbyId = await _nearby.sendFilePayload(endpointId, filePath);
      
      // Send mapping header via bytes payload
      final header = Uint8List.fromList(utf8.encode('FT_MAP:$nearbyId:$fileId'));
      await _nearby.sendBytesPayload(endpointId, header);
      
      // Track our own progress mapping
      _nearbyIdToFileId[nearbyId] = fileId;
      _nearbyIdToEndpointId[nearbyId] = endpointId;
      return true;
    } catch (e) {
      AppLogger.print('Error in WiFiTransport.sendFile: $e');
      return false;
    }
  }

  Future<bool> _enqueuePayload({
    required String endpointId,
    required Uint8List data,
    required bool isControl,
  }) {
    if (!_connectedPeers.containsKey(endpointId)) return Future.value(false);

    final completer = Completer<bool>();
    final frame = _OutboundFrame(
      endpointId: endpointId,
      data: data,
      completer: completer,
    );
    if (isControl) {
      _controlSendQueue.addLast(frame);
    } else {
      _bulkSendQueue.addLast(frame);
    }
    _drainOutboundQueue();
    return completer.future;
  }

  void _drainOutboundQueue() {
    if (_outboundPumpActive) return;
    _outboundPumpActive = true;

    unawaited(() async {
      while (_controlSendQueue.isNotEmpty || _bulkSendQueue.isNotEmpty) {
        final frame = _controlSendQueue.isNotEmpty 
            ? _controlSendQueue.removeFirst() 
            : _bulkSendQueue.removeFirst();

        if (!_connectedPeers.containsKey(frame.endpointId)) {
          frame.completer.complete(false);
          continue;
        }

        try {
          await _nearby.sendBytesPayload(frame.endpointId, frame.data);
          _updateActivity(frame.endpointId);
          frame.completer.complete(true);
        } catch (e) {
          frame.completer.complete(false);
        }
      }
      _outboundPumpActive = false;
    }());
  }

  void _dropQueuedFramesForEndpoint(String endpointId, {bool bulkOnly = false}) {
    if (!bulkOnly) {
      _controlSendQueue.removeWhere((f) => f.endpointId == endpointId);
    }
    _bulkSendQueue.removeWhere((f) => f.endpointId == endpointId);
  }

  void _clearQueuedFrames() {
    _controlSendQueue.clear();
    _bulkSendQueue.clear();
  }

  @override
  List<String> getConnectedPeerIds() => _connectedPeers.values.toList();

  void setLocalIdentity(String peerId, String name) {
    _localName = name;
    if (_isAdvertising) {
      unawaited(_restartAdvertising());
    }
  }

  @override
  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {
    _dropQueuedFramesForEndpoint(peerId, bulkOnly: bulkOnly);
  }
  @override
  Future<void> dispose() async {
    _keepaliveTimer?.cancel();
    _healthCheckTimer?.cancel();
    _reconnectCheckTimer?.cancel();
    _clearQueuedFrames();
    _nearbyIdToFileId.clear();
    _nearbyIdToLocalPath.clear();
    await _nearby.stopAllEndpoints();
    await _messageController.close();
    await _fileProgressController.close();
  }
}

class _OutboundFrame {
  final String endpointId;
  final Uint8List data;
  final Completer<bool> completer;
  _OutboundFrame({required this.endpointId, required this.data, required this.completer});
}

class WiFiDiscoveryFailure {
  final WiFiDiscoveryFailureCode code;
  final String details;
  const WiFiDiscoveryFailure({required this.code, required this.details});

  bool get isLocationRelated =>
      code == WiFiDiscoveryFailureCode.locationPermissionMissing ||
      code == WiFiDiscoveryFailureCode.locationServiceDisabled;

  String get userMessage {
    switch (code) {
      case WiFiDiscoveryFailureCode.locationPermissionMissing:
        return "Location permission is required for WiFi Direct.";
      case WiFiDiscoveryFailureCode.locationServiceDisabled:
        return "Location services are disabled. Please enable them.";
    }
  }
  static WiFiDiscoveryFailure? fromError(String raw) {
    if (raw.contains('PERMISSION')) return WiFiDiscoveryFailure(code: WiFiDiscoveryFailureCode.locationPermissionMissing, details: raw);
    return null;
  }
}

enum WiFiDiscoveryFailureCode { locationPermissionMissing, locationServiceDisabled }
