import 'dart:typed_data';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import 'crypto_service.dart';
import '../models/mesh_message.dart';
import 'package:uuid/uuid.dart';

class DeliveryAckHandler {
  final DBService _db;
  final CryptoService _cryptoService;
  final _uuid = const Uuid();

  DeliveryAckHandler(this._db, this._cryptoService);

  // Generate acknowledgment for delivered message
  Future<MeshMessage> createAcknowledgment(MeshMessage originalMessage) async {
    final ackId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Create acknowledgment message with original message ID in content
    final ackContent = 'ACK:${originalMessage.messageId}';
    final encryptedContent = _cryptoService.encryptContent(
      ackContent,
      await _getPublicKeyFromPeerId(originalMessage.senderPeerId),
    );

    final ackMessage = MeshMessage(
      messageId: ackId,
      type: MessageType.acknowledgment,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: originalMessage.senderPeerId,
      ttl: 8,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: Uint8List(0), // Temporary, will be signed
    );

    // Sign the acknowledgment
    final signature = _cryptoService.signMessage(ackMessage.toBytesForSigning());
    
    return MeshMessage(
      messageId: ackId,
      type: MessageType.acknowledgment,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: originalMessage.senderPeerId,
      ttl: 8,
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
    final senderPublicKey = await _getPublicKeyFromPeerId(ackMessage.senderPeerId);
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
    notifyDeliveryConfirmed(originalMessageId);
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
  void notifyDeliveryConfirmed(String messageId) {
    // TODO: Implement notification via Provider/Stream
    // This will be wired up when integrating with AppState
    print('Message $messageId delivered successfully');
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

  // Clean up old pending acknowledgments (older than 48 hours)
  Future<void> cleanupOldAcks() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(const Duration(hours: 48))
        .millisecondsSinceEpoch;

    await database.delete(
      'pending_acks',
      where: 'sent_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  // Get statistics
  Future<Map<String, int>> getStats() async {
    final database = await _db.db;
    
    final pendingCount = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM pending_acks'),
    ) ?? 0;

    return {
      'pending_acks': pendingCount,
    };
  }

  // Helper to get public key from peer ID
  Future<Uint8List> _getPublicKeyFromPeerId(String peerId) async {
    // Peer ID is base64-encoded public key
    return Uint8List.fromList(base64.decode(peerId));
  }
}
