import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Database;
import '../models/mesh_message.dart';
import '../models/communication_mode.dart';
import '../models/runtime_profile.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
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
      StreamController<Map<String, Object?>>.broadcast(sync: true);

  static const int _maxBroadcastsPerMinute = BroadcastLimits.maxPerMinute;
  static const int _maxGlobalBroadcastRows = BroadcastLimits.maxGlobalRows;
  static const int _maxBroadcastRowsPerSender =
      BroadcastLimits.maxRowsPerSender;
  final Map<String, List<int>> _senderBroadcastTimestamps = {};
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;

  Stream<Map<String, Object?>> get onBroadcastMessage =>
      _broadcastStreamController.stream;
  int get maxBroadcastsPerMinute => _maxBroadcastsPerMinute;
  EmergencyBroadcastTiming get _timing =>
      TimerConfig.emergencyBroadcast(_runtimeProfile);

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
        _db = db {
    unawaited(_pruneStoredBroadcasts());
  }

  void setRuntimeProfile(RuntimeProfile profile) {
    _runtimeProfile = profile;
  }

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
      ttl: BroadcastLimits.messageTtl,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      encryptedContent: Uint8List.fromList(utf8.encode(content)),
      signature: Uint8List(0),
      expiryDuration: TimerConfig.emergencyRetentionWindow.inMilliseconds,
    );
    final signed = message.copyWithSignature(
      _cryptoService.signMessage(message.toBytesForSigning()),
    );
    await _persistBroadcast(signed);
    return _forwardBroadcastWithQueueWindow(signed);
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
    if (message.hopCount > BroadcastLimits.probabilisticDecayHopThreshold &&
        Random().nextDouble() > BroadcastLimits.probabilisticDecayDropChance) {
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
    final fanoutRange =
        BroadcastLimits.fanoutMax - BroadcastLimits.fanoutMin + 1;
    final targetFanout = BroadcastLimits.fanoutMin + rng.nextInt(fanoutRange);
    final count = candidates.length < BroadcastLimits.fanoutMax
        ? candidates.length
        : targetFanout;
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

  /// Try sending broadcast immediately, then keep retrying for a short queue
  /// window to catch transient transport recoveries before declaring failure.
  Future<bool> _forwardBroadcastWithQueueWindow(MeshMessage message) async {
    if (await _forwardBroadcast(message, null)) {
      return true;
    }

    final timing = _timing;
    final deadline = DateTime.now().add(timing.queueWindow);
    debugPrint(
        'EmergencyBroadcast: queued for retry window (${timing.queueWindow.inSeconds}s), retry every ${timing.retryInterval.inSeconds}s');

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(timing.retryInterval);
      if (await _forwardBroadcast(message, null)) {
        debugPrint('EmergencyBroadcast: delivered during retry window');
        return true;
      }
    }

    debugPrint(
        'EmergencyBroadcast: retry window exhausted, marking send as failed');
    return false;
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

    await _enforceRetentionPolicy(database);
  }

  Future<void> _pruneStoredBroadcasts() async {
    final database = await _db.db;
    await _enforceRetentionPolicy(database);
  }

  Future<void> _enforceRetentionPolicy(Database database) async {
    final cutoff = DateTime.now()
        .subtract(TimerConfig.emergencyRetentionWindow)
        .millisecondsSinceEpoch;
    await database.delete(
      'broadcast_messages',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );

    // Enforce per-sender hard cap for all senders.
    final senderRows = await database.rawQuery('''
      SELECT DISTINCT sender_id
      FROM broadcast_messages
    ''');
    for (final row in senderRows) {
      final sender = row['sender_id'] as String?;
      if (sender == null || sender.isEmpty) continue;
      await database.rawDelete('''
        DELETE FROM broadcast_messages
        WHERE sender_id = ?
          AND id NOT IN (
            SELECT id
            FROM broadcast_messages
            WHERE sender_id = ?
            ORDER BY timestamp DESC
            LIMIT ?
          )
      ''', [sender, sender, _maxBroadcastRowsPerSender]);
    }

    await database.rawDelete('''
      DELETE FROM broadcast_messages
      WHERE id NOT IN (
        SELECT id
        FROM broadcast_messages
        ORDER BY timestamp DESC
        LIMIT ?
      )
    ''', [_maxGlobalBroadcastRows]);
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
    final windowStart = now -
        EmergencyBroadcastPolicyConfig.senderRateLimitWindow.inMilliseconds;
    final timestamps =
        _senderBroadcastTimestamps.putIfAbsent(senderId, () => []);
    timestamps.removeWhere((ts) => ts < windowStart);
    return timestamps;
  }

  void dispose() {
    _broadcastStreamController.close();
  }
}
