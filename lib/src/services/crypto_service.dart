import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium/sodium.dart';

class CryptoService {
  final Sodium _sodium;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  KeyPair? _encryptionKeyPair;
  KeyPair? _signingKeyPair;

  CryptoService(this._sodium);

  // Initialize and load or generate keypairs
  Future<void> init() async {
    await _ensureEncryptionKeypair();
    await _ensureSigningKeypair();
  }

  // Get public keys
  Uint8List get encryptionPublicKey => _encryptionKeyPair!.publicKey;
  Uint8List get signingPublicKey => _signingKeyPair!.publicKey;

  // Ensure encryption keypair exists (X25519 for crypto_box)
  Future<void> _ensureEncryptionKeypair() async {
    final stored = await _secureStorage.read(key: 'identity_keypair');
    if (stored != null) {
      final parts = stored.split('|');
      if (parts.length == 2) {
        final private = base64Decode(parts[0]);
        final public = base64Decode(parts[1]);
        _encryptionKeyPair = KeyPair(
          publicKey: Uint8List.fromList(public),
          secretKey: SecureKey.fromList(_sodium, private),
        );
        return;
      }
    }

    // Generate new encryption keypair
    final keypair = _sodium.crypto.box.keyPair();
    await _secureStorage.write(
      key: 'identity_keypair',
      value: '${base64Encode(keypair.secretKey.extractBytes())}|${base64Encode(keypair.publicKey)}',
    );
    _encryptionKeyPair = keypair;
  }

  // Ensure signing keypair exists (Ed25519 for crypto_sign)
  Future<void> _ensureSigningKeypair() async {
    final stored = await _secureStorage.read(key: 'signing_keypair');
    if (stored != null) {
      final parts = stored.split('|');
      if (parts.length == 2) {
        final private = base64Decode(parts[0]);
        final public = base64Decode(parts[1]);
        _signingKeyPair = KeyPair(
          publicKey: Uint8List.fromList(public),
          secretKey: SecureKey.fromList(_sodium, private),
        );
        return;
      }
    }

    // Generate new signing keypair
    final keypair = _sodium.crypto.sign.keyPair();
    await _secureStorage.write(
      key: 'signing_keypair',
      value: '${base64Encode(keypair.secretKey.extractBytes())}|${base64Encode(keypair.publicKey)}',
    );
    _signingKeyPair = keypair;
  }

  // Encrypt message content using recipient's public key
  Uint8List encryptContent(String content, Uint8List recipientPublicKey) {
    final contentBytes = Uint8List.fromList(utf8.encode(content));
    final nonce = _sodium.randombytes.buf(24); // 24-byte nonce for crypto_box
    
    final ciphertext = _sodium.crypto.box.easy(
      message: contentBytes,
      nonce: nonce,
      publicKey: recipientPublicKey,
      secretKey: _encryptionKeyPair!.secretKey,
    );
    
    // Prepend nonce to ciphertext for transmission
    return Uint8List.fromList([...nonce, ...ciphertext]);
  }

  // Decrypt message content using sender's public key
  String decryptContent(Uint8List encryptedData, Uint8List senderPublicKey) {
    if (encryptedData.length < 24) {
      throw Exception('Invalid encrypted data: too short');
    }
    
    final nonce = encryptedData.sublist(0, 24);
    final ciphertext = encryptedData.sublist(24);
    
    final plaintext = _sodium.crypto.box.openEasy(
      cipherText: ciphertext,
      nonce: nonce,
      publicKey: senderPublicKey,
      secretKey: _encryptionKeyPair!.secretKey,
    );
    
    return utf8.decode(plaintext);
  }

  // Encrypt raw bytes using recipient's public key
  Uint8List encryptBytes(Uint8List data, Uint8List recipientPublicKey) {
    final nonce = _sodium.randombytes.buf(24);
    
    final ciphertext = _sodium.crypto.box.easy(
      message: data,
      nonce: nonce,
      publicKey: recipientPublicKey,
      secretKey: _encryptionKeyPair!.secretKey,
    );
    
    return Uint8List.fromList([...nonce, ...ciphertext]);
  }

  // Decrypt raw bytes using sender's public key
  Uint8List decryptBytes(Uint8List encryptedData, Uint8List senderPublicKey) {
    if (encryptedData.length < 24) {
      throw Exception('Invalid encrypted data: too short');
    }
    
    final nonce = encryptedData.sublist(0, 24);
    final ciphertext = encryptedData.sublist(24);
    
    return _sodium.crypto.box.openEasy(
      cipherText: ciphertext,
      nonce: nonce,
      publicKey: senderPublicKey,
      secretKey: _encryptionKeyPair!.secretKey,
    );
  }

  // Sign message using signing keypair
  Uint8List signMessage(Uint8List messageBytes) {
    return _sodium.crypto.sign.detached(
      message: messageBytes,
      secretKey: _signingKeyPair!.secretKey,
    );
  }

  // Verify signature using sender's public key
  bool verifySignature(Uint8List messageBytes, Uint8List signature, Uint8List senderPublicKey) {
    try {
      return _sodium.crypto.sign.verifyDetached(
        signature: signature,
        message: messageBytes,
        publicKey: senderPublicKey,
      );
    } catch (e) {
      return false;
    }
  }

  // Helper to get peer ID from signing public key (base64 encoded)
  String getPeerId(Uint8List signingPublicKey) {
    return base64Encode(signingPublicKey);
  }

  // Get local peer ID
  String get localPeerId => getPeerId(_signingKeyPair!.publicKey);

  // Helper methods
  static Uint8List base64Decode(String s) => Uint8List.fromList(base64.decode(s));
  static String base64Encode(Uint8List b) => base64.encode(b);
}
