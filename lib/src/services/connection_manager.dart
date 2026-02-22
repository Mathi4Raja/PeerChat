import 'dart:async';
import 'package:flutter/foundation.dart';
import 'db_service.dart';
import 'crypto_service.dart';
import '../models/peer.dart';
import '../models/handshake_message.dart';

/// Manages peer connections and ID mappings
/// Maps transport IDs (MAC addresses, endpoint IDs) to cryptographic peer IDs
class ConnectionManager extends ChangeNotifier {
  final DBService _db;
  final CryptoService _crypto;
  
  // Map transport ID -> crypto peer ID
  final Map<String, String> _transportToCrypto = {};
  
  // Map crypto peer ID -> transport ID
  final Map<String, String> _cryptoToTransport = {};
  
  // Track which peers have completed handshake
  final Set<String> _handshakeComplete = {};
  
  // Display name for handshakes
  String _displayName = 'PeerChat User';
  
  // Callback for sending handshake messages
  Function(String transportId, Uint8List data)? onSendHandshake;

  // Callback for when handshake is complete and peer ID is known
  Function(String peerId)? onHandshakeComplete;

  ConnectionManager(this._db, this._crypto);
  
  /// Update display name for handshakes
  void setDisplayName(String name) {
    _displayName = name;
  }

  /// Get cryptographic peer ID from transport ID
  String? getCryptoPeerId(String transportId) {
    return _transportToCrypto[transportId];
  }

  /// Get transport ID from cryptographic peer ID
  String? getTransportId(String cryptoPeerId) {
    return _cryptoToTransport[cryptoPeerId];
  }

  /// Check if handshake is complete for a transport connection
  bool isHandshakeComplete(String transportId) {
    return _handshakeComplete.contains(transportId);
  }

  /// Handle new connection - send handshake
  Future<void> onConnectionEstablished(String transportId) async {
    debugPrint('Connection established with $transportId, sending handshake');
    
    // Create handshake message with both signing and encryption public keys
    final handshake = HandshakeMessage(
      peerId: _crypto.localPeerId,
      publicKey: _crypto.signingPublicKey,
      encryptionPublicKey: _crypto.encryptionPublicKey,
      displayName: _displayName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    // Send handshake
    if (onSendHandshake != null) {
      onSendHandshake!(transportId, handshake.toBytes());
    }
  }

  /// Handle received handshake message
  Future<void> handleHandshake(String transportId, HandshakeMessage handshake) async {
    debugPrint('Received handshake from $transportId: ${handshake.displayName}');
    
    // Validate timestamp (not older than 5 minutes)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - handshake.timestamp > 300000) {
      debugPrint('Handshake rejected: too old');
      return;
    }

    // Store mapping (update if transport ID changed)
    final oldTransportId = _cryptoToTransport[handshake.peerId];
    if (oldTransportId != null && oldTransportId != transportId) {
      debugPrint('Transport ID changed: $oldTransportId -> $transportId');
      _transportToCrypto.remove(oldTransportId);
      _handshakeComplete.remove(oldTransportId);
    }
    
    _transportToCrypto[transportId] = handshake.peerId;
    _cryptoToTransport[handshake.peerId] = transportId;
    _handshakeComplete.add(transportId);

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
    onHandshakeComplete?.call(handshake.peerId);
    notifyListeners();
  }

  /// Handle connection lost
  void onConnectionLost(String transportId) {
    debugPrint('Connection lost with $transportId');
    
    final cryptoId = _transportToCrypto[transportId];
    if (cryptoId != null) {
      _cryptoToTransport.remove(cryptoId);
    }
    _transportToCrypto.remove(transportId);
    _handshakeComplete.remove(transportId);
    
    notifyListeners();
  }
  
  /// Update peer's lastSeen timestamp (call when receiving data/keepalives)
  Future<void> updatePeerActivity(String transportId) async {
    final cryptoId = _transportToCrypto[transportId];
    if (cryptoId == null) {
      debugPrint('⚠️ updatePeerActivity: No crypto ID for transport $transportId');
      return;
    }
    
    // Get all peers and find the one we need to update
    final peers = await _db.allPeers();
    final peer = peers.where((p) => p.id == cryptoId).firstOrNull;
    
    if (peer != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final updatedPeer = Peer(
        id: peer.id,
        displayName: peer.displayName,
        address: peer.address,
        lastSeen: now,
        hasApp: peer.hasApp,
      );
      await _db.upsertPeer(updatedPeer);
      debugPrint('✓ Updated peer activity: ${peer.displayName} (${peer.id.substring(0, 8)}) lastSeen=$now');
      notifyListeners(); // Notify listeners so AppState can react
    } else {
      debugPrint('⚠️ updatePeerActivity: Peer not found for crypto ID ${cryptoId.substring(0, 8)}');
    }
  }

  /// Get all connected crypto peer IDs
  List<String> getConnectedCryptoPeerIds() {
    return _cryptoToTransport.keys.toList();
  }

  /// Get all connected transport IDs
  List<String> getConnectedTransportIds() {
    return _transportToCrypto.keys.toList();
  }
}
