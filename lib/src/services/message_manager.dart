import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'crypto_service.dart';
import 'route_manager.dart';
import 'message_queue.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import '../config/limits_config.dart';
import '../models/mesh_message.dart';
import '../models/queued_message.dart';
import 'package:uuid/uuid.dart';

enum ProcessResult {
  delivered,
  forwarded,
  queued,
  duplicate,
  expired,
  invalid,
}

class MessageManager {
  final CryptoService _cryptoService;
  final RouteManager _routeManager;
  final MessageQueue _messageQueue;
  final DeduplicationCache _deduplicationCache;
  final SignatureVerifier _signatureVerifier;

  final _uuid = const Uuid();
  final _random = Random.secure();

  static const int maxMessageSize = MessageLimits.maxContentBytes;

  final Future<bool> Function(String peerId, Uint8List data)
      sendTransportMessage;

  MessageManager(
    this._cryptoService,
    this._routeManager,
    this._messageQueue,
    this._deduplicationCache,
    this._signatureVerifier,
    this.sendTransportMessage,
  );

  // Create and encrypt a new message (text-based)
  Future<MeshMessage> createMessage({
    required String recipientPeerId,
    required Uint8List recipientPublicKey,
    required String content,
    required MessagePriority priority,
    String? messageId,
  }) async {
    if (content.length > maxMessageSize) {
      throw Exception('Message exceeds maximum size of $maxMessageSize bytes');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final id = messageId ?? _generateMessageId();

    final ttlRange = MessageLimits.ttlMax - MessageLimits.ttlMin + 1;
    final ttl = MessageLimits.ttlMin + _random.nextInt(ttlRange);

    final recipientEncryptionKey =
        await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
    if (recipientEncryptionKey == null) {
      throw Exception('Encryption key not found for peer $recipientPeerId');
    }

    final encryptedContent = _cryptoService.encryptContent(
      content,
      recipientEncryptionKey,
    );

    final unsignedMessage = MeshMessage(
      messageId: id,
      type: MessageType.data,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl,
      hopCount: 0,
      priority: priority,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: Uint8List(0),
    );

    final signature =
        _cryptoService.signMessage(unsignedMessage.toBytesForSigning());

    return unsignedMessage.copyWithSignature(signature);
  }

  /// Create and encrypt a message with arbitrary byte data and custom type
  Future<MeshMessage> createDataMessage({
    required String recipientPeerId,
    required Uint8List recipientPublicKey,
    required Uint8List data,
    required MessageType type,
    required MessagePriority priority,
    String? messageId,
  }) async {
    if (data.length > maxMessageSize) {
      throw Exception('Data exceeds maximum size of $maxMessageSize bytes');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final msgId = messageId ?? _generateMessageId();

    final ttlRange = MessageLimits.ttlMax - MessageLimits.ttlMin + 1;
    final ttl = MessageLimits.ttlMin + _random.nextInt(ttlRange);

    final recipientEncryptionKey =
        await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
    if (recipientEncryptionKey == null) {
      throw Exception('Encryption key not found for peer $recipientPeerId');
    }

    final encryptedContent = _cryptoService.encryptBytes(
      data,
      recipientEncryptionKey,
    );

    final unsignedMessage = MeshMessage(
      messageId: msgId,
      type: type,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl,
      hopCount: 0,
      priority: priority,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: Uint8List(0),
    );

    final signature =
        _cryptoService.signMessage(unsignedMessage.toBytesForSigning());

    return unsignedMessage.copyWithSignature(signature);
  }

  String _generateMessageId() {
    final localId = _cryptoService.localPeerId;
    final shortSenderId =
        localId.length >= MessageLimits.generatedIdSenderPrefixLength
            ? localId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
            : localId;
    final compactUuid = _uuid
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    return '${shortSenderId}_$compactUuid';
  }

  // Process incoming message
  Future<ProcessResult> processMessage(
      MeshMessage message, String fromPeerAddress) async {
    // Verify signature
    final isValidSignature =
        await _signatureVerifier.verifyMessageSignature(message);
    if (!isValidSignature) {
      debugPrint('Invalid signature from ${message.senderPeerId}');
      await _signatureVerifier.recordInvalidSignature(message.senderPeerId);
      return ProcessResult.invalid;
    }

    // Check expiry
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - message.timestamp;
    if (age < -MessageLimits.futureClockSkewToleranceMs || message.isExpired) {
      return ProcessResult.expired;
    }

    // Check deduplication
    if (await _deduplicationCache.hasSeen(message.messageId)) {
      return ProcessResult.duplicate;
    }
    await _deduplicationCache.markSeen(message.messageId, message.timestamp);

    // Check TTL
    if (message.ttl <= 0) {
      return ProcessResult.expired;
    }

    // Check if we are the destination
    if (message.recipientPeerId == _cryptoService.localPeerId) {
      return ProcessResult.delivered;
    }

    // Relay
    return ProcessResult.queued;
  }

  // Decrypt text content
  Future<String?> decryptContent(MeshMessage message) async {
    if (message.recipientPeerId != _cryptoService.localPeerId ||
        message.encryptedContent == null) {
      return null;
    }

    try {
      final senderEncryptionKey =
          await _signatureVerifier.getPeerEncryptionKey(message.senderPeerId);
      if (senderEncryptionKey == null) return null;

      return _cryptoService.decryptContent(
        message.encryptedContent!,
        senderEncryptionKey,
      );
    } catch (e) {
      debugPrint('Decryption error: $e');
      return null;
    }
  }

  // Decrypt raw bytes content
  Future<Uint8List?> decryptBytes(MeshMessage message) async {
    if (message.recipientPeerId != _cryptoService.localPeerId ||
        message.encryptedContent == null) {
      return null;
    }

    try {
      final senderEncryptionKey =
          await _signatureVerifier.getPeerEncryptionKey(message.senderPeerId);
      if (senderEncryptionKey == null) return null;

      return _cryptoService.decryptBytes(
        message.encryptedContent!,
        senderEncryptionKey,
      );
    } catch (e) {
      debugPrint('Byte decryption error: $e');
      return null;
    }
  }

  Future<bool> forwardMessage(MeshMessage message) async {
    final nextHop = await _routeManager.getNextHop(message.recipientPeerId);
    if (nextHop == null) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: _queueOriginFor(message),
      );
      await _messageQueue.enqueue(queuedMessage);
      _routeManager.discoverRoute(message.recipientPeerId);
      return false;
    }

    final sent = await sendTransportMessage(nextHop, message.toBytes());
    if (!sent) {
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: nextHop,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: _queueOriginFor(message),
      );
      await _messageQueue.enqueue(queuedMessage);
      return false;
    }
    return true;
  }

  QueueOrigin _queueOriginFor(MeshMessage message) {
    return message.senderPeerId == _cryptoService.localPeerId
        ? QueueOrigin.local
        : QueueOrigin.mesh;
  }
}
