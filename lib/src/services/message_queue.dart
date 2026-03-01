import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import '../models/queued_message.dart';
import '../models/mesh_message.dart';
import '../config/limits_config.dart';
import '../config/protocol_config.dart';

class QueueStats {
  final int totalMessages;
  final int highPriority;
  final int normalPriority;
  final int lowPriority;
  final int localOriginMessages;
  final int meshOriginMessages;

  QueueStats({
    required this.totalMessages,
    required this.highPriority,
    required this.normalPriority,
    required this.lowPriority,
    required this.localOriginMessages,
    required this.meshOriginMessages,
  });
}

class MessageQueue {
  final DBService _db;
  static const int maxQueueSize = QueueLimits.maxQueueSize;

  /// Maximum messages per destination peer — prevents single unreachable peer
  /// from consuming the entire queue.
  static const int maxMessagesPerPeer = QueueLimits.maxMessagesPerPeer;

  MessageQueue(this._db);

  // Add message to queue
  Future<void> enqueue(QueuedMessage message) async {
    final database = await _db.db;
    await database.insert(
      'message_queue',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enforceQueueLimit();
    await _enforcePerPeerLimit(message.nextHopPeerId);
  }

  // Enforce maximum queue size, dropping oldest lowest priority messages first
  Future<void> _enforceQueueLimit() async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
        ) ??
        0;

    if (count > maxQueueSize) {
      final excess = count - maxQueueSize;

      // Delete oldest, lowest priority messages
      await database.rawDelete('''
        DELETE FROM message_queue
        WHERE message_id IN (
          SELECT message_id FROM message_queue
          ORDER BY priority ASC, queued_timestamp ASC
          LIMIT ?
        )
      ''', [excess]);
    }
  }

  // Get messages ready for transmission to a specific peer
  Future<List<QueuedMessage>> getMessagesForPeer(String peerId) async {
    final database = await _db.db;
    final results = await database.query(
      'message_queue',
      where: 'next_hop_peer_id = ?',
      whereArgs: [peerId],
      orderBy: 'priority DESC, queued_timestamp ASC',
    );

    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  // Remove message from queue after successful transmission
  Future<void> dequeue(String messageId) async {
    final database = await _db.db;
    await database.delete(
      'message_queue',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  // Get all queued messages sorted by priority and timestamp
  Future<List<QueuedMessage>> getAllQueued() async {
    final database = await _db.db;
    final results = await database.query(
      'message_queue',
      orderBy: 'priority DESC, queued_timestamp ASC',
    );

    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  /// Get messages that are ready for retry (past their nextRetryTime).
  /// Filters out messages that haven't reached their backoff time yet.
  Future<List<QueuedMessage>> getReadyMessages() async {
    return _queryReadyMessages();
  }

  /// Get ready messages for a specific queue origin.
  Future<List<QueuedMessage>> getReadyMessagesByOrigin(
      QueueOrigin origin) async {
    return _queryReadyMessages(origin: origin);
  }

  Future<List<QueuedMessage>> _queryReadyMessages({QueueOrigin? origin}) async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final whereOrigin = origin == null ? '' : ' AND origin_type = ?';
    final args = <Object?>[
      now,
      now,
      if (origin != null) origin.index,
      now,
    ];
    final results = await database.rawQuery('''
      SELECT * FROM message_queue
      WHERE next_retry_time <= ?
        AND (expiry_time = 0 OR expiry_time > ?)$whereOrigin
      ORDER BY
        (priority + CASE WHEN (? - queued_timestamp) >= ${QueuePolicyConfig.stalePriorityBoostAgeMs} THEN 1 ELSE 0 END) DESC,
        queued_timestamp ASC
    ''', args);

    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  // Remove expired messages based on each message's duration-based expiry.
  // Returns message IDs that were dropped.
  Future<List<String>> removeExpired() async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final droppedIds = <String>{};

    final expiredRows = await database.query(
      'message_queue',
      columns: ['message_id'],
      where: 'expiry_time > 0 AND expiry_time <= ?',
      whereArgs: [now],
    );
    for (final row in expiredRows) {
      final id = row['message_id'] as String?;
      if (id != null && id.isNotEmpty) {
        droppedIds.add(id);
      }
    }
    if (droppedIds.isNotEmpty) {
      await database.delete(
        'message_queue',
        where: 'expiry_time > 0 AND expiry_time <= ?',
        whereArgs: [now],
      );
    }

    // Legacy rows without expiry_time still use message payload duration check.
    final legacyRows = await database.query(
      'message_queue',
      where: 'expiry_time = 0',
    );
    for (final row in legacyRows) {
      final queued = QueuedMessage.fromMap(row);
      if (queued.isExpired) {
        droppedIds.add(queued.message.messageId);
        await dequeue(queued.message.messageId);
      }
    }
    return droppedIds.toList();
  }

  // Update attempt count with exponential backoff
  // Returns true if the message was dropped due to exceeding retry limit.
  Future<bool> updateAttempt(String messageId) async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Get current attempt count
    final result = await database.query(
      'message_queue',
      columns: ['attempt_count'],
      where: 'message_id = ?',
      whereArgs: [messageId],
    );

    final currentAttempts =
        result.isNotEmpty ? (result.first['attempt_count'] as int? ?? 0) : 0;
    final newAttempts = currentAttempts + 1;

    // Check if should drop (exceeded max retries)
    if (newAttempts > QueuedMessage.maxRetries) {
      await dequeue(messageId);
      return true;
    }

    // Exponential backoff: base * 2^min(retryCount, 10)
    // Caps at ~30s * 1024 ≈ 8.5 hours max delay
    final backoffMs = QueuedMessage.baseRetryInterval *
        (1 <<
            (newAttempts < QueueLimits.backoffExponentCap
                ? newAttempts
                : QueueLimits.backoffExponentCap));
    final nextRetryTime = now + backoffMs;

    await database.rawUpdate('''
      UPDATE message_queue
      SET attempt_count = ?,
          last_attempt_timestamp = ?,
          next_retry_time = ?
      WHERE message_id = ?
    ''', [newAttempts, now, nextRetryTime, messageId]);
    return false;
  }

  /// Enforce per-destination queue limit. Drops oldest messages for a peer
  /// when they exceed maxMessagesPerPeer.
  Future<void> _enforcePerPeerLimit(String peerId) async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE next_hop_peer_id = ?',
            [peerId],
          ),
        ) ??
        0;

    if (count > maxMessagesPerPeer) {
      final excess = count - maxMessagesPerPeer;
      await database.rawDelete('''
        DELETE FROM message_queue
        WHERE message_id IN (
          SELECT message_id FROM message_queue
          WHERE next_hop_peer_id = ?
          ORDER BY priority ASC, queued_timestamp ASC
          LIMIT ?
        )
      ''', [peerId, excess]);
    }
  }

  // Get queue statistics
  Future<QueueStats> getStats() async {
    final database = await _db.db;

    final totalCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
        ) ??
        0;

    final highCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
            [MessagePriority.high.index],
          ),
        ) ??
        0;

    final normalCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
            [MessagePriority.normal.index],
          ),
        ) ??
        0;

    final lowCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
            [MessagePriority.low.index],
          ),
        ) ??
        0;

    final localOriginCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE origin_type = ?',
            [QueueOrigin.local.index],
          ),
        ) ??
        0;

    final meshOriginCount = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE origin_type = ?',
            [QueueOrigin.mesh.index],
          ),
        ) ??
        0;

    return QueueStats(
      totalMessages: totalCount,
      highPriority: highCount,
      normalPriority: normalCount,
      lowPriority: lowCount,
      localOriginMessages: localOriginCount,
      meshOriginMessages: meshOriginCount,
    );
  }

  // Check if queue has messages for a specific peer
  Future<bool> hasPendingMessagesForPeer(String peerId) async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM message_queue WHERE next_hop_peer_id = ?',
            [peerId],
          ),
        ) ??
        0;

    return count > 0;
  }

  // Get count of messages in queue
  Future<int> getQueueSize() async {
    final database = await _db.db;
    return Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
        ) ??
        0;
  }
}
