import 'dart:typed_data';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'crypto_service.dart';
import 'db_service.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import '../models/mesh_message.dart';
import '../models/route_discovery.dart';

class SignatureVerifier {
  final CryptoService _cryptoService;
  final DBService _db;

  static const int maxInvalidSignatures = SecurityLimits.maxInvalidSignatures;
  static const Duration blockDuration =
      SecurityTimerConfig.invalidSignatureBlockDuration;
  static const Duration detectionWindow =
      SecurityTimerConfig.invalidSignatureDetectionWindow;

  SignatureVerifier(this._cryptoService, this._db);

  // Verify message signature
  Future<bool> verifyMessageSignature(MeshMessage message) async {
    final senderPublicKey = await getPeerPublicKey(message.senderPeerId);
    if (senderPublicKey == null) {
      return false;
    }

    final messageBytes = message.toBytesForSigning();
    return _cryptoService.verifySignature(
      messageBytes,
      message.signature,
      senderPublicKey,
    );
  }

  // Verify route advertisement signature
  Future<bool> verifyRouteSignature(RouteResponse response) async {
    final responderPublicKey = await getPeerPublicKey(response.responderPeerId);
    if (responderPublicKey == null) {
      return false;
    }

    final responseBytes = response.toBytesForSigning();
    return _cryptoService.verifySignature(
      responseBytes,
      response.signature,
      responderPublicKey,
    );
  }

  // Verify route request signature
  Future<bool> verifyRouteRequestSignature(RouteRequest request) async {
    final requestorPublicKey = await getPeerPublicKey(request.requestorPeerId);
    if (requestorPublicKey == null) {
      return false;
    }

    final requestBytes = request.toBytesForSigning();
    return _cryptoService.verifySignature(
      requestBytes,
      request.signature,
      requestorPublicKey,
    );
  }

  // Get public key for a peer ID
  Future<Uint8List?> getPeerPublicKey(String peerId) async {
    // First try to get from database
    final key = await _db.getPeerPublicKey(peerId);
    if (key != null) return key;

    // Fallback: try to decode peer ID as public key (identity = signing key)
    try {
      return Uint8List.fromList(base64.decode(peerId));
    } catch (e) {
      return null;
    }
  }

  Future<Uint8List?> getPeerEncryptionKey(String peerId) async {
    // Try to get from database
    return await _db.getPeerEncryptionKey(peerId);
  }

  // Track invalid signature attempts
  Future<void> recordInvalidSignature(String peerId) async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowStart = now - detectionWindow.inMilliseconds;

    // Get recent invalid signature count
    final result = await database.query(
      'blocked_peers',
      where: 'peer_id = ? AND blocked_until_timestamp > ?',
      whereArgs: [peerId, windowStart],
    );

    int invalidCount = 1;
    if (result.isNotEmpty) {
      invalidCount = (result.first['invalid_signature_count'] as int) + 1;
    }

    // Block peer if threshold exceeded
    if (invalidCount >= maxInvalidSignatures) {
      final blockUntil = now + blockDuration.inMilliseconds;
      await database.insert(
        'blocked_peers',
        {
          'peer_id': peerId,
          'blocked_until_timestamp': blockUntil,
          'invalid_signature_count': invalidCount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      // Update count but don't block yet
      final tempBlockUntil = now + detectionWindow.inMilliseconds;
      await database.insert(
        'blocked_peers',
        {
          'peer_id': peerId,
          'blocked_until_timestamp': tempBlockUntil,
          'invalid_signature_count': invalidCount,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // Check if peer is temporarily blocked
  Future<bool> isPeerBlocked(String peerId) async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    final result = await database.query(
      'blocked_peers',
      where: 'peer_id = ? AND blocked_until_timestamp > ?',
      whereArgs: [peerId, now],
    );

    if (result.isEmpty) {
      return false;
    }

    final invalidCount = result.first['invalid_signature_count'] as int;
    return invalidCount >= maxInvalidSignatures;
  }

  // Unblock peers after timeout
  Future<void> unblockExpiredPeers() async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await database.delete(
      'blocked_peers',
      where: 'blocked_until_timestamp <= ?',
      whereArgs: [now],
    );
  }

  // Get blocked peers statistics
  Future<Map<String, dynamic>> getStats() async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    final blockedCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM blocked_peers WHERE blocked_until_timestamp > ? AND invalid_signature_count >= ?',
            [now, maxInvalidSignatures],
          ),
        ) ??
        0;

    return {
      'blocked_peers': blockedCount,
    };
  }
}
