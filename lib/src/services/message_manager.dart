import 'dart:math';
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

  // Create and encrypt a new message
  Future<MeshMessage> createMessage({
    required String recipientPeerId,
    required Uint8List recipientPublicKey,
    required String content,
    required MessagePriority priority,
    String? messageId,
  }) async {
    // Validate message size
    if (content.length > maxMessageSize) {
      throw Exception('Message exceeds maximum size of $maxMessageSize bytes');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Keep wire-compatible message IDs (<= 36 chars).
    final localId = _cryptoService.localPeerId;
    final shortSenderId =
        localId.length >= MessageLimits.generatedIdSenderPrefixLength
            ? localId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
            : localId;
    final compactUuid = _uuid
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    final id = messageId ?? '${shortSenderId}_$compactUuid';

    // Random TTL between configured min/max hops.
    final ttlRange = MessageLimits.ttlMax - MessageLimits.ttlMin + 1;
    final ttl = MessageLimits.ttlMin + _random.nextInt(ttlRange);

    // Get recipient's encryption public key
    final recipientEncryptionKey =
        await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
    if (recipientEncryptionKey == null) {
      throw Exception(
          'Encryption key not found for peer $recipientPeerId. Handshake may be incomplete.');
    }

    // Encrypt content
    final encryptedContent = _cryptoService.encryptContent(
      content,
      recipientEncryptionKey,
    );

    // Create message without signature first
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

    // Sign the message
    final signature =
        _cryptoService.signMessage(unsignedMessage.toBytesForSigning());

    return MeshMessage(
      messageId: id,
      type: MessageType.data,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl,
      hopCount: 0,
      priority: priority,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: signature,
    );
  }

  // Process incoming message
  Future<ProcessResult> processMessage(
      MeshMessage message, String fromPeerAddress) async {
    // Check if peer is blocked
    if (await _signatureVerifier.isPeerBlocked(message.senderPeerId)) {
      return ProcessResult.invalid;
    }

    // Verify signature (uses signing key)
    final isValidSignature =
        await _signatureVerifier.verifyMessageSignature(message);
    if (!isValidSignature) {
      debugPrint('Invalid signature from ${message.senderPeerId}');
      await _signatureVerifier.recordInvalidSignature(message.senderPeerId);
      return ProcessResult.invalid;
    }

    // Check timestamp validity with duration-based expiry.
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - message.timestamp;
    // Future tolerance: 5 minutes (clock skew guard)
    if (age < -MessageLimits.futureClockSkewToleranceMs || message.isExpired) {
      debugPrint('Message hard-expired or from future: $age ms');
      return ProcessResult.expired;
    }

    // Check deduplication
    if (await _deduplicationCache.hasSeen(message.messageId)) {
      return ProcessResult.duplicate;
    }

    // Mark as seen, anchoring cache lifespan heavily to the original message creation time
    await _deduplicationCache.markSeen(message.messageId, message.timestamp);

    // Check TTL
    if (message.ttl <= 0) {
      return ProcessResult.expired;
    }

    // Check if we are the destination
    if (message.recipientPeerId == _cryptoService.localPeerId) {
      if (message.type == MessageType.data) {
        return ProcessResult.delivered;
      }
      // Ignore legacy delivery/read control messages.
      return ProcessResult.duplicate;
    }

    // We are a relay - forward the message
    final forwardedMessage = message.copyForForwarding();
    final forwarded = await forwardMessage(forwardedMessage);

    return forwarded ? ProcessResult.forwarded : ProcessResult.queued;
  }

  // Forward message to next hop
  Future<bool> forwardMessage(MeshMessage message) async {
    // Get next hop
    final nextHop = await _routeManager.getNextHop(message.recipientPeerId);

    if (nextHop == null) {
      // No route available - queue message and initiate discovery
      final queuedMessage = QueuedMessage(
        message: message,
        nextHopPeerId: message.recipientPeerId,
        queuedTimestamp: DateTime.now().millisecondsSinceEpoch,
        origin: _queueOriginFor(message),
      );
      await _messageQueue.enqueue(queuedMessage);

      // Initiate route discovery
      _routeManager.discoverRoute(message.recipientPeerId);

      return false;
    }

    // Send message to next hop via transport layer
    final sent = await sendTransportMessage(nextHop, message.toBytes());

    if (!sent) {
      debugPrint('Transport send failed to $nextHop, queuing message');
      // If send failed, queue it
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

  // Decrypt message content (only if we are the recipient)
  Future<String?> decryptContent(MeshMessage message) async {
    if (message.recipientPeerId != _cryptoService.localPeerId) {
      return null; // Not the recipient
    }

    if (message.encryptedContent == null) {
      return null;
    }

    try {
      // Use encryption public key for decryption
      final senderEncryptionKey =
          await _signatureVerifier.getPeerEncryptionKey(message.senderPeerId);
      if (senderEncryptionKey == null) {
        debugPrint(
            'Encryption key not found for sender ${message.senderPeerId}');
        return null;
      }

      return _cryptoService.decryptContent(
        message.encryptedContent!,
        senderEncryptionKey,
      );
    } catch (e) {
      debugPrint('Decryption error: $e');
      return null;
    }
  }

  QueueOrigin _queueOriginFor(MeshMessage message) {
    return message.senderPeerId == _cryptoService.localPeerId
        ? QueueOrigin.local
        : QueueOrigin.mesh;
  }
}
