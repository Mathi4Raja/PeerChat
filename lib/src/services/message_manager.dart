import 'dart:math';
import 'package:flutter/foundation.dart';
import 'crypto_service.dart';
import 'route_manager.dart';
import 'message_queue.dart';
import 'deduplication_cache.dart';
import 'signature_verifier.dart';
import 'delivery_ack_handler.dart';
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
  final DeliveryAckHandler _deliveryAckHandler;
  
  final _uuid = const Uuid();
  final _random = Random.secure();
  
  static const int maxMessageSize = 65536; // 64 KB
  
  final Future<bool> Function(String peerId, Uint8List data) sendTransportMessage;

  MessageManager(
    this._cryptoService,
    this._routeManager,
    this._messageQueue,
    this._deduplicationCache,
    this._signatureVerifier,
    this._deliveryAckHandler,
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

    final id = messageId ?? _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Random TTL between 8-16 hops
    final ttl = 8 + _random.nextInt(9);

    // Get recipient's encryption public key
    final recipientEncryptionKey = await _signatureVerifier.getPeerEncryptionKey(recipientPeerId);
    if (recipientEncryptionKey == null) {
      throw Exception('Encryption key not found for peer $recipientPeerId. Handshake may be incomplete.');
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
    final signature = _cryptoService.signMessage(unsignedMessage.toBytesForSigning());

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
  Future<ProcessResult> processMessage(MeshMessage message, String fromPeerAddress) async {
    // Check if peer is blocked
    if (await _signatureVerifier.isPeerBlocked(message.senderPeerId)) {
      return ProcessResult.invalid;
    }

    // Verify signature (uses signing key)
    final isValidSignature = await _signatureVerifier.verifyMessageSignature(message);
    if (!isValidSignature) {
      debugPrint('Invalid signature from ${message.senderPeerId}');
      await _signatureVerifier.recordInvalidSignature(message.senderPeerId);
      return ProcessResult.invalid;
    }

    // Check timestamp validity (not older than 5 minutes or in future)
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - message.timestamp;
    if (age > 300000 || age < -60000) {
      debugPrint('Message expired or from future: $age ms');
      return ProcessResult.invalid;
    }

    // Check deduplication
    if (await _deduplicationCache.hasSeen(message.messageId)) {
      return ProcessResult.duplicate;
    }

    // Mark as seen
    await _deduplicationCache.markSeen(message.messageId);

    // Check TTL
    if (message.ttl <= 0) {
      return ProcessResult.expired;
    }

    // Check if we are the destination
    if (message.recipientPeerId == _cryptoService.localPeerId) {
      // Deliver to local user
      if (message.type == MessageType.data) {
        // Generate acknowledgment
        final ack = await _deliveryAckHandler.createAcknowledgment(message);
        await forwardMessage(ack);
      } else if (message.type == MessageType.acknowledgment) {
        await _deliveryAckHandler.handleAcknowledgment(message);
      } else if (message.type == MessageType.readReceipt) {
        // No special direct logic here, just mark as delivered to pass to router
      }
      return ProcessResult.delivered;
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
      final senderEncryptionKey = await _signatureVerifier.getPeerEncryptionKey(message.senderPeerId);
      if (senderEncryptionKey == null) {
        debugPrint('Encryption key not found for sender ${message.senderPeerId}');
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
}
