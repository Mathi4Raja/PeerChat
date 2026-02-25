import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import '../models/queued_message.dart';
import '../models/mesh_message.dart';

class QueueStats {
  final int totalMessages;
  final int highPriority;
  final int normalPriority;
  final int lowPriority;

  QueueStats({
    required this.totalMessages,
    required this.highPriority,
    required this.normalPriority,
    required this.lowPriority,
  });
}

class MessageQueue {
  final DBService _db;
  static const int maxQueueSize = 5000;

  /// Maximum messages per destination peer — prevents single unreachable peer
  /// from consuming the entire queue.
  static const int maxMessagesPerPeer = 50;

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
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final results = await database.rawQuery('''
      SELECT * FROM message_queue
      WHERE next_retry_time <= ?
        AND (expiry_time = 0 OR expiry_time > ?)
      ORDER BY
        (priority + CASE WHEN (? - queued_timestamp) >= 3600000 THEN 1 ELSE 0 END) DESC,
        queued_timestamp ASC
    ''', [now, now, now]);

    return results.map((map) => QueuedMessage.fromMap(map)).toList();
  }

  // Remove expired messages based on each message's duration-based expiry.
  Future<void> removeExpired() async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.delete(
      'message_queue',
      where: 'expiry_time > 0 AND expiry_time <= ?',
      whereArgs: [now],
    );

    // Legacy rows without expiry_time still use message payload duration check.
    final legacyRows = await database.query(
      'message_queue',
      where: 'expiry_time = 0',
    );
    for (final row in legacyRows) {
      final queued = QueuedMessage.fromMap(row);
      if (queued.isExpired) {
        await dequeue(queued.message.messageId);
      }
    }
  }

  // Update attempt count with exponential backoff
  Future<void> updateAttempt(String messageId) async {
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
      return;
    }

    // Exponential backoff: base * 2^min(retryCount, 10)
    // Caps at ~30s * 1024 ≈ 8.5 hours max delay
    final backoffMs = QueuedMessage.baseRetryInterval *
        (1 << (newAttempts < 10 ? newAttempts : 10));
    final nextRetryTime = now + backoffMs;

    await database.rawUpdate('''
      UPDATE message_queue
      SET attempt_count = ?,
          last_attempt_timestamp = ?,
          next_retry_time = ?
      WHERE message_id = ?
    ''', [newAttempts, now, nextRetryTime, messageId]);
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

    return QueueStats(
      totalMessages: totalCount,
      highPriority: highCount,
      normalPriority: normalCount,
      lowPriority: lowCount,
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
