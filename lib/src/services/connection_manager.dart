import 'dart:async';
import 'package:flutter/foundation.dart';
import 'db_service.dart';
import 'crypto_service.dart';
import '../models/peer.dart';
import '../models/handshake_message.dart';
import '../models/runtime_profile.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import '../config/limits_config.dart';
import '../config/identity_ui_config.dart';
import '../models/peer_connection_state.dart';
import '../utils/state_guard.dart';
import 'dart:collection';

class _TaskQueue {
  final Queue<_Task> _tasks = Queue();
  bool _isProcessing = false;

  Future<void> enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _tasks.add(_Task(action, completer));
    _process();
    return completer.future;
  }

  Future<void> _process() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      while (_tasks.isNotEmpty) {
        final task = _tasks.removeFirst();
        try {
          await task.action();
          task.completer.complete();
        } catch (e, st) {
          task.completer.completeError(e, st);
        }
      }
    } finally {
      _isProcessing = false;
    }
  }
}

class _Task {
  final Future<void> Function() action;
  final Completer<void> completer;
  _Task(this.action, this.completer);
}

/// Manages peer connections and ID mappings
/// Maps transport IDs (MAC addresses, endpoint IDs) to cryptographic peer IDs
class ConnectionManager extends ChangeNotifier {
  final DBService _db;
  final CryptoService _crypto;

  // Map transport ID -> crypto peer ID
  final Map<String, String> _transportToCrypto = {};

  final _TaskQueue _stateQueue = _TaskQueue();

  // Map crypto peer ID -> currently preferred transport ID
  final Map<String, String> _cryptoToTransport = {};
  final Map<String, Set<String>> _peerTransports = {};
  final Map<String, PeerConnectionState> _transportStates = {};

  // Track which peers have completed handshake
  final Set<String> _handshakeComplete = {};
  final Set<String> _initialHandshakeSent = {};

  // Peer capability cache keyed by crypto peer ID.
  final Map<String, RuntimeProfile> _peerRuntimeProfiles = {};

  // Display name for handshakes
  String _displayName = IdentityUiConfig.defaultDisplayName;
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;

  // Callback for sending handshake messages
  Function(String transportId, Uint8List data)? onSendHandshake;

  // Callback for when handshake is complete and peer ID is known
  Function(String peerId)? onHandshakeComplete;

  ConnectionManager(this._db, this._crypto);

  /// Update display name for handshakes
  void setDisplayName(String name) {
    _displayName = name;
  }

  /// Update local runtime profile used in outbound handshake capabilities.
  /// If changed, immediately re-broadcast to connected peers.
  void setRuntimeProfile(RuntimeProfile profile) {
    if (_runtimeProfile == profile) return;
    _runtimeProfile = profile;
    notifyListeners();
    unawaited(broadcastCapabilityUpdate());
    Timer(ConnectionManagerTimerConfig.capabilityRebroadcastDelay, () {
      if (_runtimeProfile == profile) {
        unawaited(broadcastCapabilityUpdate());
      }
    });
  }

  /// Get cryptographic peer ID from transport ID
  String? getCryptoPeerId(String transportId) {
    return _transportToCrypto[transportId];
  }

  /// Get transport ID from cryptographic peer ID
  String? getTransportId(String cryptoPeerId) {
    _updatePreferredTransportForPeer(cryptoPeerId);
    return _cryptoToTransport[cryptoPeerId];
  }

  /// Check if handshake is complete for a transport connection
  bool isHandshakeComplete(String transportId) {
    return _handshakeComplete.contains(transportId);
  }

  bool hasSentInitialHandshake(String transportId) {
    return _initialHandshakeSent.contains(transportId);
  }

  Future<void> sendHandshake({
    required String transportId,
    required String reason,
    bool force = false,
  }) async {
    if (!force && !_initialHandshakeSent.add(transportId)) {
      return;
    }
    if (force) {
      _initialHandshakeSent.add(transportId);
    }
    debugPrint('Sending handshake to $transportId ($reason)');
    await _sendHandshake(transportId);
  }

  /// Handle new connection - send handshake
  Future<void> onConnectionEstablished(String transportId) async {
    return _stateQueue.enqueue(() async {
      final currentState = _transportStates[transportId] ?? PeerConnectionState.disconnected;
      StateGuard.transitionConnection(transportId, currentState, PeerConnectionState.connecting);
      _transportStates[transportId] = PeerConnectionState.connecting;
      
      StateGuard.transitionConnection(transportId, PeerConnectionState.connecting, PeerConnectionState.handshake_pending);
      _transportStates[transportId] = PeerConnectionState.handshake_pending;

      await sendHandshake(
        transportId: transportId,
        reason: 'connection_established',
      );
    });
  }

  Future<void> _sendHandshake(String transportId) async {
    // Create handshake message with both signing and encryption public keys
    final handshake = HandshakeMessage(
      peerId: _crypto.localPeerId,
      publicKey: _crypto.signingPublicKey,
      encryptionPublicKey: _crypto.encryptionPublicKey,
      displayName: _displayName,
      runtimeProfile: _runtimeProfile.storageValue,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Send handshake
    if (onSendHandshake != null) {
      onSendHandshake!(transportId, handshake.toBytes());
    }
  }

  /// Broadcast local capability/profile updates to all currently connected peers.
  Future<void> broadcastCapabilityUpdate() async {
    final transports = getConnectedTransportIds();
    for (final transportId in transports) {
      await _sendHandshake(transportId);
    }
  }

  /// Handle received handshake message
  Future<void> handleHandshake(
      String transportId, HandshakeMessage handshake) async {
    return _stateQueue.enqueue(() async {
    debugPrint(
        'Received handshake from $transportId: ${handshake.displayName}');
    final wasComplete = _handshakeComplete.contains(transportId);
    final previousPeerId = _transportToCrypto[transportId];

    // Validate timestamp (not older than 5 minutes)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - handshake.timestamp > ConnectionLimits.handshakeMaxAgeMs) {
      debugPrint('Handshake rejected: too old');
      return;
    }

    // Store mapping (update if transport ID changed) using peerId merge guard.
    _mergeSessionsByPeerId(
      peerId: handshake.peerId,
      newTransportId: transportId,
    );
    
    final currentState = _transportStates[transportId] ?? PeerConnectionState.disconnected;
    // Allow transitioning to connected from handshake_pending or connecting (if we received it before we sent ours)
    if (currentState != PeerConnectionState.connected) {
      StateGuard.transitionConnection(transportId, currentState, PeerConnectionState.connected);
      _transportStates[transportId] = PeerConnectionState.connected;
    }

    _peerRuntimeProfiles[handshake.peerId] =
        runtimeProfileFromStorage(handshake.runtimeProfile);

    // Delete old peer entry with transport ID (if exists)
    await _db.deletePeer(transportId);

    // Save peer to database with crypto ID and public key
    final peer = Peer(
      id: handshake.peerId, // Use crypto ID as primary ID
      displayName: handshake.displayName,
      address: transportId, // Store transport ID as address
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      hasApp: true, // They have the app if they sent handshake
    );

    await _db.upsertPeer(peer);

    // Save both public keys
    await _db.savePeerKeys(
      peerId: handshake.peerId,
      signingKey: handshake.publicKey,
      encryptionKey: handshake.encryptionPublicKey,
    );

    debugPrint('Handshake complete: ${handshake.peerId} <-> $transportId');
    if (!wasComplete || previousPeerId != handshake.peerId) {
      onHandshakeComplete?.call(handshake.peerId);
    }
    notifyListeners();
    });
  }

  /// Merge transport sessions by stable crypto peerId.
  /// If the same peer reconnects on a different transport, atomically swap
  /// transport mapping to prevent duplicate peer sessions.
  void _mergeSessionsByPeerId({
    required String peerId,
    required String newTransportId,
  }) {
    final previousPeerForTransport = _transportToCrypto[newTransportId];
    if (previousPeerForTransport != null &&
        previousPeerForTransport != peerId) {
      final previousSet = _peerTransports[previousPeerForTransport];
      previousSet?.remove(newTransportId);
      if (previousSet != null && previousSet.isEmpty) {
        _peerTransports.remove(previousPeerForTransport);
      }
      _updatePreferredTransportForPeer(previousPeerForTransport);
    }

    _transportToCrypto[newTransportId] = peerId;
    _peerTransports.putIfAbsent(peerId, () => <String>{}).add(newTransportId);
    _handshakeComplete.add(newTransportId);
    _updatePreferredTransportForPeer(peerId);
  }

  /// Handle connection lost.
  ///
  /// Only removes transport→crypto mapping. The crypto→transport mapping
  /// is intentionally preserved so that if the same peer reconnects via a
  /// different transport (WiFi → BT switch), we atomically update the mapping
  /// in handleHandshake() instead of creating a duplicate peer entry.
  void onConnectionLost(String transportId) {
    _stateQueue.enqueue(() async {
      debugPrint('Connection lost with $transportId');
      
      final currentState = _transportStates[transportId] ?? PeerConnectionState.disconnected;
      if (currentState != PeerConnectionState.disconnected) {
        if (currentState == PeerConnectionState.connected) {
           StateGuard.transitionConnection(transportId, currentState, PeerConnectionState.disconnecting);
           _transportStates[transportId] = PeerConnectionState.disconnecting;
        }
        StateGuard.transitionConnection(transportId, _transportStates[transportId]!, PeerConnectionState.disconnected);
        _transportStates[transportId] = PeerConnectionState.disconnected;
      }

    final cryptoId = _transportToCrypto[transportId];
    if (cryptoId != null) {
      final transports = _peerTransports[cryptoId];
      if (transports != null) {
        transports.remove(transportId);
        if (transports.isEmpty) {
          _peerTransports.remove(cryptoId);
        }
      }
      _updatePreferredTransportForPeer(cryptoId);
    }
    _transportToCrypto.remove(transportId);
    _handshakeComplete.remove(transportId);
    _initialHandshakeSent.remove(transportId);

    notifyListeners();
    });
  }

  /// Update peer's lastSeen timestamp (call when receiving data/keepalives)
  Future<void> updatePeerActivity(String transportId) async {
    return _stateQueue.enqueue(() async {
    final cryptoId = _transportToCrypto[transportId];
    if (cryptoId == null) {
      debugPrint(
          '⚠️ updatePeerActivity: No crypto ID for transport $transportId');
      return;
    }

    // Get all peers and find the one we need to update
    final peers = await _db.allPeers();
    final peer = peers.where((p) => p.id == cryptoId).firstOrNull;

    if (peer != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final shortPeerId = peer.id.length >= IdentityUiConfig.shortIdLength
          ? peer.id.substring(0, IdentityUiConfig.shortIdLength)
          : peer.id;
      final updatedPeer = Peer(
        id: peer.id,
        displayName: peer.displayName,
        address: peer.address,
        lastSeen: now,
        hasApp: peer.hasApp,
      );
      await _db.upsertPeer(updatedPeer);
      debugPrint(
          '✓ Updated peer activity: ${peer.displayName} ($shortPeerId) lastSeen=$now');
      notifyListeners(); // Notify listeners so AppState can react
    } else {
      final shortCryptoId = cryptoId.length >= IdentityUiConfig.shortIdLength
          ? cryptoId.substring(0, IdentityUiConfig.shortIdLength)
          : cryptoId;
      debugPrint(
          '⚠️ updatePeerActivity: Peer not found for crypto ID $shortCryptoId');
    }
    });
  }

  /// Get all connected crypto peer IDs
  List<String> getConnectedCryptoPeerIds() {
    return _peerTransports.keys.toList();
  }

  /// Get all connected transport IDs
  List<String> getConnectedTransportIds() {
    return _transportToCrypto.keys.toList();
  }

  RuntimeProfile? getPeerRuntimeProfile(String peerId) {
    return _peerRuntimeProfiles[peerId];
  }

  void _updatePreferredTransportForPeer(String peerId) {
    final transports = _peerTransports[peerId];
    if (transports == null || transports.isEmpty) {
      _cryptoToTransport.remove(peerId);
      return;
    }

    String? selected = _cryptoToTransport[peerId];
    if (selected != null && _transportToCrypto[selected] != peerId) {
      selected = null;
    }

    selected ??= transports.firstWhere(
      (transportId) => _transportToCrypto[transportId] == peerId,
      orElse: () => '',
    );
    if (selected.isEmpty) {
      _cryptoToTransport.remove(peerId);
      return;
    }

    _cryptoToTransport[peerId] = selected;
  }
}
