import 'dart:typed_data';
import 'dart:convert';

/// Handshake message exchanged when peers first connect
/// Contains public key and display name
class HandshakeMessage {
  final String peerId; // Cryptographic peer ID (public key hash)
  final Uint8List publicKey; // Ed25519 public key for signing
  final Uint8List encryptionPublicKey; // X25519 public key for encryption
  final String displayName; // Human-readable name
  final int timestamp;

  HandshakeMessage({
    required this.peerId,
    required this.publicKey,
    required this.encryptionPublicKey,
    required this.displayName,
    required this.timestamp,
  });

  // Serialize to bytes for transmission
  Uint8List toBytes() {
    final json = jsonEncode({
      'type': 'handshake',
      'peerId': peerId,
      'publicKey': base64Encode(publicKey),
      'encryptionPublicKey': base64Encode(encryptionPublicKey),
      'displayName': displayName,
      'timestamp': timestamp,
    });
    return Uint8List.fromList(utf8.encode(json));
  }

  // Deserialize from bytes
  static HandshakeMessage? fromBytes(Uint8List bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json['type'] != 'handshake') return null;
      
      return HandshakeMessage(
        peerId: json['peerId'],
        publicKey: Uint8List.fromList(base64Decode(json['publicKey'])),
        encryptionPublicKey: Uint8List.fromList(base64Decode(json['encryptionPublicKey'])),
        displayName: json['displayName'],
        timestamp: json['timestamp'],
      );
    } catch (e) {
      return null;
    }
  }
}
