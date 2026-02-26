import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/timer_config.dart';
import '../config/identity_ui_config.dart';
import '../config/protocol_config.dart';
import 'transport_service.dart';
import 'db_service.dart';

class WiFiTransport implements TransportService {
  final Nearby _nearby = Nearby();
  final StreamController<TransportMessage> _messageController =
      StreamController.broadcast();
  final Map<String, String> _connectedPeers = {}; // endpointId -> peerId
  final Function(String peerId, String address)? onPeerDiscovered;
  final DBService _db = DBService();

  // Callback for when connection is established
  Function(String transportId)? onConnectionEstablished;

  // Callback for when connection is lost
  Function(String transportId)? onConnectionLost;

  // Callback for discovery failures that require user action.
  Function(WiFiDiscoveryFailure failure)? onDiscoveryFailure;

  // Keepalive mechanism
  Timer? _keepaliveTimer;
  Timer? _healthCheckTimer;
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
  int _lastDiscoveryRefreshTimestamp = 0;
  int _lastDiscoveryFailureNoticeAt = 0;

  WiFiTransport({this.onPeerDiscovered});

  @override
  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  @override
  Future<void> init() async {
    try {
      // Load known peers from database
      _knownPeers = await _db.getKnownWiFiEndpoints();
      debugPrint(
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
      debugPrint('Error initializing WiFi Direct: $e');
    }
  }

  void _startReconnectionCheck() {
    // Periodically check reconnect state and refresh discovery if needed.
    Timer.periodic(WiFiTimerConfig.reconnectCheckInterval, (timer) async {
      debugPrint('=== RECONNECTION CHECK ===');
      debugPrint('Known peers: ${_knownPeers.length}');
      debugPrint('Connected peers: ${_connectedPeers.length}');
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
              debugPrint(
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
        final elapsed = nowMs - _lastDiscoveryRefreshTimestamp;
        if (elapsed > WiFiTimerConfig.discoveryRefreshCooldown.inMilliseconds) {
          _lastDiscoveryRefreshTimestamp = nowMs;
          debugPrint('No active peers. Proactively refreshing WiFi Direct...');
          await restartWiFiDirect();
        }
      }

      debugPrint('=== END RECONNECTION CHECK ===');
    });
  }

  void _startKeepalive() {
    _keepaliveTimer =
        Timer.periodic(WiFiTimerConfig.keepAliveInterval, (timer) {
      _sendKeepalives();
    });
    debugPrint(
        'WiFi Direct keepalive started (every ${WiFiTimerConfig.keepAliveInterval.inSeconds}s)');
  }

  void _startHealthCheck() {
    _healthCheckTimer =
        Timer.periodic(WiFiTimerConfig.healthCheckInterval, (timer) {
      _checkConnectionHealth();
    });
    debugPrint('WiFi Direct health check started');
  }

  void _checkConnectionHealth() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final timeoutMs = WiFiTimerConfig.connectionTimeout.inMilliseconds;
    final staleConnections = <String>[];
    final orphanedActivity = <String>[];

    debugPrint('=== CONNECTION HEALTH CHECK ===');
    debugPrint('Connected peers: ${_connectedPeers.length}');

    // Check for stale connections
    for (final entry in _lastActivity.entries) {
      // Check if this activity entry has a corresponding connected peer
      if (!_connectedPeers.containsKey(entry.key)) {
        debugPrint('  ${entry.key}: ORPHANED (no connection)');
        orphanedActivity.add(entry.key);
        continue;
      }

      final timeSinceActivity = now - entry.value;
      final secondsSinceActivity = (timeSinceActivity / 1000).round();
      debugPrint(
          '  ${entry.key}: ${secondsSinceActivity}s since last activity');

      if (timeSinceActivity > timeoutMs) {
        debugPrint(
            '  ⚠️ TIMEOUT: ${entry.key} (${secondsSinceActivity}s > ${WiFiTimerConfig.connectionTimeout.inSeconds}s)');
        staleConnections.add(entry.key);
      }
    }

    if (staleConnections.isEmpty && orphanedActivity.isEmpty) {
      debugPrint('All connections healthy');
    }
    debugPrint('=== END HEALTH CHECK ===');

    // Clean up orphaned activity entries
    for (final endpointId in orphanedActivity) {
      debugPrint('Cleaning up orphaned activity entry: $endpointId');
      _lastActivity.remove(endpointId);
    }

    // Disconnect stale connections
    for (final endpointId in staleConnections) {
      _handleConnectionTimeout(endpointId);
    }
  }

  void _handleConnectionTimeout(String endpointId) {
    debugPrint('Disconnecting stale connection: $endpointId');
    _connectedPeers.remove(endpointId);
    _lastActivity.remove(endpointId);

    // Notify connection lost
    if (onConnectionLost != null) {
      onConnectionLost!(endpointId);
    }

    // Try to disconnect from the endpoint
    try {
      _nearby.disconnectFromEndpoint(endpointId);
    } catch (e) {
      debugPrint('Error disconnecting endpoint: $e');
    }
  }

  void _updateActivity(String endpointId) {
    _lastActivity[endpointId] = DateTime.now().millisecondsSinceEpoch;
  }

  void _sendKeepalives() {
    if (_connectedPeers.isEmpty) return;

    final now = DateTime.now();
    debugPrint(
        '=== SENDING KEEPALIVES at ${now.hour}:${now.minute}:${now.second} ===');
    debugPrint('Sending to ${_connectedPeers.length} peers');

    for (final endpointId in _connectedPeers.keys) {
      try {
        _nearby.sendBytesPayload(endpointId, keepAlivePacket);
        // Update activity on successful send to prevent self-timeout
        _updateActivity(endpointId);
        debugPrint('  ✓ Sent keepalive to $endpointId');
      } catch (e) {
        debugPrint('  ✗ Error sending keepalive to $endpointId: $e');
        // Don't update activity if send failed
      }
    }
    debugPrint('=== END KEEPALIVES ===');
  }

  void setLocalIdentity(String peerId, String name) {
    _localName = name;

    // Restart advertising with new name if already advertising
    if (_isAdvertising) {
      _restartAdvertising();
    }
  }

  Future<void> restartWiFiDirect() async {
    debugPrint('Restarting WiFi Direct advertising and discovery...');
    try {
      // Reset in-flight attempt state to avoid request deadlocks after process restart.
      _pendingConnectionAttempts.clear();
      _pendingAttemptStartedAt.clear();
      _lastConnectionAttempt.clear();

      // Stop current advertising and discovery
      if (_isAdvertising) {
        await _nearby.stopAdvertising();
        _isAdvertising = false;
      }
      if (_isDiscovering) {
        await _nearby.stopDiscovery();
        _isDiscovering = false;
      }

      // If we currently have no active logical connections, clear nearby endpoint state too.
      if (_connectedPeers.isEmpty) {
        await _nearby.stopAllEndpoints();
        _lastActivity.clear();
      }

      // Wait a moment for cleanup
      await Future.delayed(WiFiTimerConfig.restartDelay);

      // Restart advertising and discovery
      await _startAdvertising();
      await _startDiscovery();

      debugPrint('WiFi Direct restarted successfully');
    } catch (e) {
      debugPrint('Error restarting WiFi Direct: $e');
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
      debugPrint('Error restarting WiFi Direct advertising: $e');
    }
  }

  Future<void> _requestPermissions() async {
    // Request location permissions explicitly
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      debugPrint('Location permission not granted, requesting again...');
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

    debugPrint('Permissions requested');
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;

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
      debugPrint('WiFi Direct advertising started as: $userName');
    } catch (e) {
      debugPrint('Error starting WiFi Direct advertising: $e');
    }
  }

  Future<void> _startDiscovery() async {
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
      debugPrint('WiFi Direct discovery started');
    } catch (e) {
      debugPrint('Error starting WiFi Direct discovery: $e');
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
      debugPrint('Clearing stale pending WiFi connection attempt: $endpointId');
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
    return _localName!.compareTo(endpointName) > 0;
  }

  void _onEndpointFound(
      String endpointId, String endpointName, String serviceId) async {
    debugPrint('WiFi Direct endpoint found: $endpointId ($endpointName)');
    _cleanupStalePendingAttempts();

    // Notify discovery service about the peer
    if (onPeerDiscovered != null) {
      onPeerDiscovered!(endpointId, endpointName);
    }

    // Skip if already connected or currently trying.
    if (_connectedPeers.containsKey(endpointId)) {
      debugPrint(
          'Already connected to $endpointId, skipping connection request');
      return;
    }
    if (_pendingConnectionAttempts.contains(endpointId)) {
      debugPrint('Connection attempt already in progress for $endpointId');
      return;
    }

    if (_shouldWaitForRemoteInitiator(endpointName)) {
      debugPrint(
          'Waiting for remote initiator for $endpointId to avoid collision');
      return;
    }

    // Simple attempt cooldown to avoid request storms.
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAttempt = _lastConnectionAttempt[endpointId];
    if (lastAttempt != null &&
        (now - lastAttempt) <
            WiFiTimerConfig.connectionAttemptCooldown.inMilliseconds) {
      return;
    }

    // Check if we should auto-reconnect to this peer
    final shouldReconnect = await _shouldAttemptReconnect(endpointId);

    if (shouldReconnect) {
      debugPrint('Auto-reconnecting to known peer: $endpointId');
      _lastReconnectAttempt[endpointId] = now;
      await _db.incrementReconnectAttempts(endpointId);
    } else {
      debugPrint('New peer discovered, attempting initial connection');
    }

    // Request connection
    final userName = _localName ?? IdentityUiConfig.defaultDisplayName;
    _pendingConnectionAttempts.add(endpointId);
    _pendingAttemptStartedAt[endpointId] = now;
    _lastConnectionAttempt[endpointId] = now;
    try {
      await _nearby.requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      debugPrint('WiFi Direct requestConnection failed for $endpointId: $e');
      _pendingConnectionAttempts.remove(endpointId);
      _pendingAttemptStartedAt.remove(endpointId);

      final message = e.toString();
      if (message.contains('STATUS_ALREADY_CONNECTED_TO_ENDPOINT')) {
        debugPrint(
            'Nearby reported already connected for $endpointId, marking active');
        _connectedPeers[endpointId] = endpointId;
        _updateActivity(endpointId);
        _knownPeers.add(endpointId);
        await _db.saveKnownWiFiEndpoint(endpointId);
        if (onConnectionEstablished != null) {
          onConnectionEstablished!(endpointId);
        }
      }
    }
  }

  Future<bool> _shouldAttemptReconnect(String endpointId) async {
    // Don't reconnect if already connected
    if (_connectedPeers.containsKey(endpointId)) {
      return false;
    }

    // Don't reconnect if this is a new peer (never connected before)
    if (!_knownPeers.contains(endpointId)) {
      return false;
    }

    // Check if we're in cooldown period
    final lastAttempt = _lastReconnectAttempt[endpointId];
    if (lastAttempt != null) {
      final timeSinceLastAttempt =
          DateTime.now().millisecondsSinceEpoch - lastAttempt;
      if (timeSinceLastAttempt <
          WiFiTimerConfig.reconnectCooldown.inMilliseconds) {
        final remainingSeconds =
            ((WiFiTimerConfig.reconnectCooldown.inMilliseconds -
                        timeSinceLastAttempt) /
                    1000)
                .round();
        debugPrint(
            'Reconnect cooldown active for $endpointId ($remainingSeconds seconds remaining)');
        return false;
      }
    }

    return true;
  }

  void _onEndpointLost(String? endpointId) {
    debugPrint('WiFi Direct endpoint lost: $endpointId');
    if (endpointId != null) {
      _pendingConnectionAttempts.remove(endpointId);
      _pendingAttemptStartedAt.remove(endpointId);
    }
    // NOTE: Don't remove from _connectedPeers here!
    // onEndpointLost means the endpoint stopped advertising, not that the connection dropped.
    // The connection might still be active. Only remove on onDisconnected.
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) async {
    debugPrint('WiFi Direct connection initiated: $endpointId');

    // Auto-accept connections
    try {
      await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (endpointId, payload) {
          _handleIncomingPayload(endpointId, payload);
        },
      );
    } catch (e) {
      debugPrint('WiFi Direct acceptConnection failed for $endpointId: $e');
    }
  }

  void _onConnectionResult(String endpointId, Status status) async {
    _pendingConnectionAttempts.remove(endpointId);
    _pendingAttemptStartedAt.remove(endpointId);
    if (status == Status.CONNECTED) {
      debugPrint('WiFi Direct connected: $endpointId');
      _connectedPeers[endpointId] =
          endpointId; // Use endpointId as peerId for now
      _updateActivity(endpointId); // Mark initial connection time

      // Mark as known peer for future auto-reconnection (persist to database)
      _knownPeers.add(endpointId);
      await _db.saveKnownWiFiEndpoint(endpointId);
      debugPrint('Saved known WiFi endpoint to database: $endpointId');

      // Reset reconnect attempts on successful connection
      await _db.resetReconnectAttempts(endpointId);

      // Notify connection established
      if (onConnectionEstablished != null) {
        onConnectionEstablished!(endpointId);
      }
    } else {
      debugPrint(
          'WiFi Direct connection failed: $endpointId (status: $status)');
      _connectedPeers.remove(endpointId);
      _lastActivity.remove(endpointId);

      // Increment reconnect attempts on failure (if it's a known peer)
      if (_knownPeers.contains(endpointId)) {
        await _db.incrementReconnectAttempts(endpointId);
        final attempts = await _db.getReconnectAttempts(endpointId);
        debugPrint(
            'Reconnect attempt failed for $endpointId (attempts=$attempts)');
      }
    }
  }

  void _onDisconnected(String endpointId) async {
    debugPrint('WiFi Direct disconnected: $endpointId');
    _connectedPeers.remove(endpointId);
    _lastActivity.remove(endpointId);
    _pendingConnectionAttempts.remove(endpointId);
    _pendingAttemptStartedAt.remove(endpointId);

    // Mark as known peer for auto-reconnection (if it was successfully connected before)
    if (_knownPeers.contains(endpointId)) {
      debugPrint(
          'Known peer disconnected, will attempt auto-reconnect when rediscovered');
      // Reset reconnect attempts to allow fresh reconnection attempts
      await _db.resetReconnectAttempts(endpointId);
    }

    // Notify connection lost
    if (onConnectionLost != null) {
      onConnectionLost!(endpointId);
    }

    // Promptly refresh discovery/advertising for quicker reconnection.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastDiscoveryRefreshTimestamp >
        WiFiTimerConfig.discoveryRefreshCooldown.inMilliseconds) {
      _lastDiscoveryRefreshTimestamp = nowMs;
      await restartWiFiDirect();
    }
  }

  void _handleIncomingPayload(String endpointId, Payload payload) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final bytes = Uint8List.fromList(payload.bytes!);

        // Check if it's a keepalive packet
        if (bytes.length == ProtocolConfig.keepAlivePacketLength &&
            bytes[0] == ProtocolConfig.keepAliveByte &&
            bytes[1] == ProtocolConfig.keepAliveByte) {
          // Only process keepalive if this endpoint is in our connected peers
          if (_connectedPeers.containsKey(endpointId)) {
            _updateActivity(endpointId);
            final now = DateTime.now();
            debugPrint(
                '⟳ Received keepalive from $endpointId at ${now.hour}:${now.minute}:${now.second}');

            // Forward keepalive to message handler so updatePeerActivity gets called
            final message = TransportMessage(
              fromPeerId: endpointId,
              fromAddress: endpointId,
              data: bytes,
            );
            _messageController.add(message);
          } else {
            debugPrint(
                '⚠️ Received keepalive from unknown endpoint $endpointId - ignoring');
          }
          return;
        }

        // For non-keepalive data (including handshakes), always process
        // Handshakes arrive before the endpoint is added to _connectedPeers
        _updateActivity(endpointId);

        final message = TransportMessage(
          fromPeerId: endpointId,
          fromAddress: endpointId,
          data: bytes,
        );
        _messageController.add(message);
      }
    } catch (e) {
      debugPrint('Error handling WiFi Direct payload: $e');
    }
  }

  @override
  Future<bool> sendMessage(String peerId, Uint8List data) async {
    debugPrint('WiFiTransport.sendMessage to $peerId');

    // Find endpoint ID for peer
    String? endpointId;
    for (final entry in _connectedPeers.entries) {
      if (entry.value == peerId || entry.key == peerId) {
        endpointId = entry.key;
        break;
      }
    }

    if (endpointId == null) {
      debugPrint('  No endpoint found for $peerId');
      debugPrint('  Connected peers: $_connectedPeers');
      return false;
    }

    try {
      debugPrint('  Sending ${data.length} bytes to endpoint $endpointId...');
      await _nearby.sendBytesPayload(endpointId, data);
      debugPrint('  Data sent successfully');
      return true;
    } catch (e) {
      debugPrint('  Error sending: $e');
      return false;
    }
  }

  @override
  List<String> getConnectedPeerIds() {
    return _connectedPeers.values.toList();
  }

  @override
  Future<void> dispose() async {
    _keepaliveTimer?.cancel();
    _healthCheckTimer?.cancel();
    if (_isAdvertising) {
      await _nearby.stopAdvertising();
      _isAdvertising = false;
    }
    if (_isDiscovering) {
      await _nearby.stopDiscovery();
      _isDiscovering = false;
    }
    await _nearby.stopAllEndpoints();
    await _messageController.close();
  }
}

enum WiFiDiscoveryFailureCode {
  locationPermissionMissing,
  locationServiceDisabled,
}

class WiFiDiscoveryFailure {
  final WiFiDiscoveryFailureCode code;
  final String details;

  const WiFiDiscoveryFailure({
    required this.code,
    required this.details,
  });

  bool get isLocationRelated => true;

  String get userMessage {
    switch (code) {
      case WiFiDiscoveryFailureCode.locationPermissionMissing:
        return 'Peer discovery needs location permission on Android.';
      case WiFiDiscoveryFailureCode.locationServiceDisabled:
        return 'Peer discovery needs Location turned on in system settings.';
    }
  }

  static WiFiDiscoveryFailure? fromError(String rawError) {
    final upper = rawError.toUpperCase();

    var hasMissingPermissionToken = false;
    for (final token in WiFiDiscoveryErrorConfig.missingPermissionTokens) {
      if (upper.contains(token)) {
        hasMissingPermissionToken = true;
        break;
      }
    }
    if (hasMissingPermissionToken ||
        upper.contains(WiFiDiscoveryErrorConfig.missingPermissionCode)) {
      return WiFiDiscoveryFailure(
        code: WiFiDiscoveryFailureCode.locationPermissionMissing,
        details: rawError,
      );
    }

    var hasLocationDisabledToken = false;
    for (final token in WiFiDiscoveryErrorConfig.locationDisabledTokens) {
      if (upper.contains(token)) {
        hasLocationDisabledToken = true;
        break;
      }
    }
    if (hasLocationDisabledToken) {
      return WiFiDiscoveryFailure(
        code: WiFiDiscoveryFailureCode.locationServiceDisabled,
        details: rawError,
      );
    }

    return null;
  }
}
