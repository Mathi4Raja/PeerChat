import 'dart:typed_data';
import 'mesh_message.dart';

class QueuedMessage {
  final MeshMessage message;
  final String nextHopPeerId;
  final int queuedTimestamp;
  final int attemptCount;
  final int? lastAttemptTimestamp;
  /// When this message is next eligible for retry.
  /// Uses exponential backoff: nextRetryTime = now + base * 2^min(retryCount, 10)
  final int nextRetryTime;
  /// Absolute expiry timestamp in milliseconds (for DB-level pruning).
  /// 0 means fallback to duration-based check from [MeshMessage].
  final int expiryTime;

  /// Maximum retry attempts before dropping the message.
  static const int maxRetries = 50;
  /// Base retry interval in milliseconds (30 seconds).
  static const int baseRetryInterval = 30000;

  QueuedMessage({
    required this.message,
    required this.nextHopPeerId,
    required this.queuedTimestamp,
    this.attemptCount = 0,
    this.lastAttemptTimestamp,
    this.nextRetryTime = 0,
    this.expiryTime = 0,
  });

  /// Check if message has expired (uses clock-independent duration from MeshMessage)
  bool get isExpired => message.isExpired;

  /// Check if message should be dropped (exceeded max retries)
  bool get shouldDrop => attemptCount > maxRetries;

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
      'next_retry_time': nextRetryTime,
      'expiry_time':
          expiryTime > 0 ? expiryTime : (message.timestamp + message.expiryDuration),
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
      nextRetryTime: map['next_retry_time'] as int? ?? 0,
      expiryTime: map['expiry_time'] as int? ?? 0,
    );
  }

  // Create a copy with updated fields
  QueuedMessage copyWith({
    MeshMessage? message,
    String? nextHopPeerId,
    int? queuedTimestamp,
    int? attemptCount,
    int? lastAttemptTimestamp,
    int? nextRetryTime,
    int? expiryTime,
  }) {
    return QueuedMessage(
      message: message ?? this.message,
      nextHopPeerId: nextHopPeerId ?? this.nextHopPeerId,
      queuedTimestamp: queuedTimestamp ?? this.queuedTimestamp,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptTimestamp: lastAttemptTimestamp ?? this.lastAttemptTimestamp,
      nextRetryTime: nextRetryTime ?? this.nextRetryTime,
      expiryTime: expiryTime ?? this.expiryTime,
    );
  }
}
