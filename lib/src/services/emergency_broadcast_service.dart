import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import '../models/mesh_message.dart';
import '../models/communication_mode.dart';
import 'crypto_service.dart';
import 'connection_manager.dart';
import 'transport_service.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'db_service.dart';

class EmergencyBroadcastService {
  final CryptoService _cryptoService;
  final ConnectionManager _connectionManager;
  final MultiTransportService _transportService;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;
  final DBService _db;
  final StreamController<Map<String, Object?>> _broadcastStreamController =
      StreamController<Map<String, Object?>>.broadcast();

  static const int _maxBroadcastsPerMinute = 5;
  final Map<String, List<int>> _senderBroadcastTimestamps = {};

  Stream<Map<String, Object?>> get onBroadcastMessage =>
      _broadcastStreamController.stream;

  EmergencyBroadcastService({
    required CryptoService cryptoService,
    required ConnectionManager connectionManager,
    required MultiTransportService transportService,
    required DeduplicationCache deduplicationCache,
    required SignatureVerifier signatureVerifier,
    required DBService db,
  })  : _cryptoService = cryptoService,
        _connectionManager = connectionManager,
        _transportService = transportService,
        _deduplicationCache = deduplicationCache,
        _signatureVerifier = signatureVerifier,
        _db = db;

  Future<bool> broadcastMessage({
    required String messageId,
    required String content,
  }) async {
    if (!_allowBroadcastFromSender(_cryptoService.localPeerId)) {
      debugPrint('EmergencyBroadcast: local sender rate-limited');
      return false;
    }

    final message = MeshMessage(
      messageId: messageId,
      type: MessageType.data,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: broadcastEmergencyDestination,
      ttl: 5,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      encryptedContent: Uint8List.fromList(utf8.encode(content)),
      signature: Uint8List(0),
      expiryDuration: const Duration(hours: 24).inMilliseconds,
    );
    final signed = message.copyWithSignature(
      _cryptoService.signMessage(message.toBytesForSigning()),
    );
    await _persistBroadcast(signed);
    return _forwardBroadcast(signed, null);
  }

  Future<bool> handleIncomingBroadcast(
      MeshMessage message, String fromPeerAddress) async {
    if (await _deduplicationCache.hasSeen(message.messageId)) {
      return false;
    }
    await _deduplicationCache.markSeen(message.messageId, message.timestamp);

    if (!_allowBroadcastFromSender(message.senderPeerId)) {
      debugPrint(
          'EmergencyBroadcast: dropped rate-limited sender ${message.senderPeerId}');
      return false;
    }

    final valid = await _signatureVerifier.verifyMessageSignature(message);
    if (!valid || message.ttl <= 0) return false;
    await _persistBroadcast(message);
    return _forwardBroadcast(message.copyForForwarding(), fromPeerAddress);
  }

  Future<bool> _forwardBroadcast(
      MeshMessage message, String? fromPeerAddress) async {
    if (message.ttl <= 0) return false;

    // Probabilistic decay after hop 2 to dampen dense-network amplification.
    if (message.hopCount > 2 && Random().nextDouble() > 0.5) {
      return false;
    }

    final fromCryptoId = fromPeerAddress == null
        ? null
        : _connectionManager.getCryptoPeerId(fromPeerAddress);
    final connected = _connectionManager.getConnectedCryptoPeerIds();

    final candidates = connected.where((peerId) {
      if (peerId == fromCryptoId) return false;
      if (peerId == message.senderPeerId) return false;
      if (_deduplicationCache.hasForwardedTo(message.messageId, peerId)) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return false;

    final rng = Random();
    candidates.shuffle(rng);
    final count =
        candidates.length < 3 ? candidates.length : (2 + rng.nextInt(2));
    var sentAny = false;

    for (final peerId in candidates.take(count)) {
      final transportId = _connectionManager.getTransportId(peerId);
      if (transportId == null) continue;
      final sent =
          await _transportService.sendMessage(transportId, message.toBytes());
      if (sent) {
        sentAny = true;
        _deduplicationCache.markForwardedTo(message.messageId, peerId);
      }
    }

    return sentAny;
  }

  Future<void> _persistBroadcast(MeshMessage message) async {
    if (message.encryptedContent == null) return;
    final database = await _db.db;
    await database.insert(
      'broadcast_messages',
      {
        'id': message.messageId,
        'sender_id': message.senderPeerId,
        'content': utf8.decode(message.encryptedContent!),
        'timestamp': message.timestamp,
        'signature': message.signature,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    _broadcastStreamController.add({
      'id': message.messageId,
      'sender_id': message.senderPeerId,
      'content': utf8.decode(message.encryptedContent!),
      'timestamp': message.timestamp,
      'signature': message.signature,
    });

    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    await database.delete(
      'broadcast_messages',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  bool _allowBroadcastFromSender(String senderId) {
    final timestamps = _activeTimestampsForSender(senderId);
    if (timestamps.length >= _maxBroadcastsPerMinute) return false;
    timestamps.add(DateTime.now().millisecondsSinceEpoch);
    return true;
  }

  int remainingQuotaForSender(String senderId) {
    final used = _activeTimestampsForSender(senderId).length;
    final remaining = _maxBroadcastsPerMinute - used;
    return remaining < 0 ? 0 : remaining;
  }

  bool canLocalSenderBroadcast() {
    return remainingQuotaForSender(_cryptoService.localPeerId) > 0;
  }

  List<int> _activeTimestampsForSender(String senderId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowStart = now - const Duration(minutes: 1).inMilliseconds;
    final timestamps = _senderBroadcastTimestamps.putIfAbsent(senderId, () => []);
    timestamps.removeWhere((ts) => ts < windowStart);
    return timestamps;
  }

  void dispose() {
    _broadcastStreamController.close();
  }
}
