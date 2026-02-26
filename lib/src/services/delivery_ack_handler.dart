import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import 'crypto_service.dart';
import 'signature_verifier.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import '../config/identity_ui_config.dart';
import '../models/mesh_message.dart';
import '../models/chat_message.dart';
import 'package:uuid/uuid.dart';

class DeliveryAckHandler {
  final DBService _db;
  final CryptoService _cryptoService;
  late final SignatureVerifier _signatureVerifier;
  final _uuid = const Uuid();

  Function(String messageId)? onStatusChanged;

  DeliveryAckHandler(this._db, this._cryptoService);

  /// Set the signature verifier (called after all services are initialized)
  void setSignatureVerifier(SignatureVerifier verifier) {
    _signatureVerifier = verifier;
  }

  // Generate acknowledgment for delivered message
  Future<MeshMessage> createAcknowledgment(MeshMessage originalMessage) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final senderId = _cryptoService.localPeerId;
    final shortSenderId = senderId.length >= IdentityUiConfig.shortIdLength
        ? senderId.substring(0, IdentityUiConfig.shortIdLength)
        : senderId;
    final rawUuid = _uuid.v4();
    final shortUuid = rawUuid.length >= IdentityUiConfig.shortIdLength
        ? rawUuid.substring(0, IdentityUiConfig.shortIdLength)
        : rawUuid;
    final ackId = '${timestamp}_${shortSenderId}_$shortUuid';

    // Create acknowledgment message with original message ID in content
    final ackContent = 'ACK:${originalMessage.messageId}';
    final encryptedContent = _cryptoService.encryptContent(
      ackContent,
      await _getEncryptionKeyFromPeerId(originalMessage.senderPeerId),
    );

    final ackMessage = MeshMessage(
      messageId: ackId,
      type: MessageType.acknowledgment,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: originalMessage.senderPeerId,
      ttl: MessageLimits.acknowledgmentTtl,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: Uint8List(0), // Temporary, will be signed
    );

    // Sign the acknowledgment
    final signature =
        _cryptoService.signMessage(ackMessage.toBytesForSigning());

    return MeshMessage(
      messageId: ackId,
      type: MessageType.acknowledgment,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: originalMessage.senderPeerId,
      ttl: MessageLimits.acknowledgmentTtl,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: signature,
    );
  }

  // Process received acknowledgment
  Future<void> handleAcknowledgment(MeshMessage ackMessage) async {
    // Decrypt acknowledgment content
    final senderPublicKey =
        await _getEncryptionKeyFromPeerId(ackMessage.senderPeerId);
    final ackContent = _cryptoService.decryptContent(
      ackMessage.encryptedContent!,
      senderPublicKey,
    );

    // Extract original message ID
    if (!ackContent.startsWith('ACK:')) {
      return; // Invalid acknowledgment format
    }

    final originalMessageId = ackContent.substring(4);

    // Remove from pending acknowledgments
    final database = await _db.db;
    await database.delete(
      'pending_acks',
      where: 'message_id = ?',
      whereArgs: [originalMessageId],
    );

    // Notify application layer
    await notifyDeliveryConfirmed(originalMessageId);
    onStatusChanged?.call(originalMessageId);
  }

  // Track pending acknowledgments
  Future<void> trackPendingAck(String messageId, String recipientPeerId) async {
    final database = await _db.db;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    await database.insert(
      'pending_acks',
      {
        'message_id': messageId,
        'recipient_peer_id': recipientPeerId,
        'sent_timestamp': timestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Notify application layer of delivery confirmation
  Future<void> notifyDeliveryConfirmed(String messageId) async {
    // Update chat message status in database to 'delivered'
    await _db.updateMessageStatus(messageId, MessageStatus.delivered);
    debugPrint(
        'Message $messageId delivery confirmed — status updated to delivered');

    // We don't have direct access to status controller here easily without passing it.
    // Instead, MeshRouter will listen for DB changes if needed, or we just notify.
  }

  // Get pending acknowledgments
  Future<List<Map<String, dynamic>>> getPendingAcks() async {
    final database = await _db.db;
    return await database.query('pending_acks');
  }

  // Check if acknowledgment is pending for a message
  Future<bool> isPendingAck(String messageId) async {
    final database = await _db.db;
    final result = await database.query(
      'pending_acks',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return result.isNotEmpty;
  }

  /// Remove a single pending ACK record by message ID.
  Future<int> removePendingAck(String messageId) async {
    final database = await _db.db;
    return database.delete(
      'pending_acks',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  // Clean up old pending acknowledgments (older than 7 days)
  Future<void> cleanupOldAcks() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(DeliveryAckTimerConfig.pendingAckMaxAge)
        .millisecondsSinceEpoch;

    await database.delete(
      'pending_acks',
      where: 'sent_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  /// Remove invalid pending ACK rows so "pending" truly means
  /// "already sent, waiting for delivery confirmation".
  Future<void> cleanupInvalidPendingAcks() async {
    final database = await _db.db;
    await database.rawDelete('''
      DELETE FROM pending_acks
      WHERE message_id IN (
        SELECT p.message_id
        FROM pending_acks p
        LEFT JOIN chat_messages c ON c.id = p.message_id
        WHERE c.id IS NULL
           OR c.status IN (?, ?)
      )
    ''', [
      MessageStatus.sending.index,
      MessageStatus.failed.index,
    ]);
  }

  /// Manually clear all pending acknowledgments.
  /// Returns number of deleted rows.
  Future<int> clearAllPendingAcks() async {
    final database = await _db.db;
    return database.delete('pending_acks');
  }

  // Get statistics
  Future<Map<String, int>> getStats() async {
    final database = await _db.db;

    final pendingCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM pending_acks'),
        ) ??
        0;

    return {
      'pending_acks': pendingCount,
    };
  }

  // Helper to get encryption public key from peer ID
  Future<Uint8List> _getEncryptionKeyFromPeerId(String peerId) async {
    // Peer ID is the base64-encoded SIGNING public key.
    // We explicitly need the encryption public key (X25519) for crypto_box operations.
    final key = await _signatureVerifier.getPeerEncryptionKey(peerId);
    if (key != null) {
      return key;
    }

    // Fallback: This is technically risky if we are strict about key types,
    // but if the system previously conflated them, we might have legacy data.
    // Ideally, we should throw or return null if not found, but for now we try decoding.
    // NOTE: This fallback will likely fail if data is truly Ed25519 vs Curve25519.
    try {
      return Uint8List.fromList(base64.decode(peerId));
    } catch (_) {
      throw Exception('No encryption key found for peer $peerId');
    }
  }
}
