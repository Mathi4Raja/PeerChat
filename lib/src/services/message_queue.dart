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
  }

  // Enforce maximum queue size, dropping oldest lowest priority messages first
  Future<void> _enforceQueueLimit() async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
    ) ?? 0;

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

  // Remove expired messages (older than 7 days)
  Future<void> removeExpired() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;

    await database.delete(
      'message_queue',
      where: 'queued_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  // Update attempt count for a message
  Future<void> updateAttempt(String messageId) async {
    final database = await _db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    await database.rawUpdate('''
      UPDATE message_queue
      SET attempt_count = attempt_count + 1,
          last_attempt_timestamp = ?
      WHERE message_id = ?
    ''', [now, messageId]);
  }

  // Get queue statistics
  Future<QueueStats> getStats() async {
    final database = await _db.db;
    
    final totalCount = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
    ) ?? 0;

    final highCount = Sqflite.firstIntValue(
      await database.rawQuery(
        'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
        [MessagePriority.high.index],
      ),
    ) ?? 0;

    final normalCount = Sqflite.firstIntValue(
      await database.rawQuery(
        'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
        [MessagePriority.normal.index],
      ),
    ) ?? 0;

    final lowCount = Sqflite.firstIntValue(
      await database.rawQuery(
        'SELECT COUNT(*) FROM message_queue WHERE priority = ?',
        [MessagePriority.low.index],
      ),
    ) ?? 0;

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
    ) ?? 0;

    return count > 0;
  }

  // Get count of messages in queue
  Future<int> getQueueSize() async {
    final database = await _db.db;
    return Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM message_queue'),
    ) ?? 0;
  }
}
