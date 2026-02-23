import 'dart:typed_data';
import 'mesh_message.dart';

class QueuedMessage {
  final MeshMessage message;
  final String nextHopPeerId;
  final int queuedTimestamp;
  final int attemptCount;
  final int? lastAttemptTimestamp;

  QueuedMessage({
    required this.message,
    required this.nextHopPeerId,
    required this.queuedTimestamp,
    this.attemptCount = 0,
    this.lastAttemptTimestamp,
  });

  // Check if message has expired (queued > 7 days)
  bool get isExpired {
    final now = DateTime.now().millisecondsSinceEpoch;
    final age = now - message.timestamp;
    return age > 604800000; // 7 days in milliseconds
  }

  // Serialize for database storage
  Map<String, Object?> toMap() {
    return {
      'message_id': message.messageId,
      'next_hop_peer_id': nextHopPeerId,
      'message_data': message.toBytes(),
      'priority': message.priority.index,
      'queued_timestamp': queuedTimestamp,
      'attempt_count': attemptCount,
      'last_attempt_timestamp': lastAttemptTimestamp,
    };
  }

  // Deserialize from database
  static QueuedMessage fromMap(Map<String, Object?> map) {
    final messageData = map['message_data'] as Uint8List;
    final message = MeshMessage.fromBytes(messageData);
    
    return QueuedMessage(
      message: message,
      nextHopPeerId: map['next_hop_peer_id'] as String,
      queuedTimestamp: map['queued_timestamp'] as int,
      attemptCount: map['attempt_count'] as int? ?? 0,
      lastAttemptTimestamp: map['last_attempt_timestamp'] as int?,
    );
  }

  // Create a copy with updated fields
  QueuedMessage copyWith({
    MeshMessage? message,
    String? nextHopPeerId,
    int? queuedTimestamp,
    int? attemptCount,
    int? lastAttemptTimestamp,
  }) {
    return QueuedMessage(
      message: message ?? this.message,
      nextHopPeerId: nextHopPeerId ?? this.nextHopPeerId,
      queuedTimestamp: queuedTimestamp ?? this.queuedTimestamp,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptTimestamp: lastAttemptTimestamp ?? this.lastAttemptTimestamp,
    );
  }
}
