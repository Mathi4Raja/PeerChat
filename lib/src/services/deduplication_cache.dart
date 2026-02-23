import 'package:sqflite/sqflite.dart';
import 'db_service.dart';

class DeduplicationCache {
  final DBService _db;
  static const int maxCacheSize = 10000;
  static const Duration absoluteMaxAge = Duration(days: 7);

  DeduplicationCache(this._db);

  // Check if message ID has been seen
  Future<bool> hasSeen(String messageId) async {
    final database = await _db.db;
    final result = await database.query(
      'deduplication_cache',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return result.isNotEmpty;
  }

  // Mark message ID as seen
  Future<void> markSeen(String messageId, int originalTimestamp) async {
    final database = await _db.db;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    await database.insert(
      'deduplication_cache',
      {
        'message_id': messageId,
        'seen_timestamp': timestamp,
        'original_timestamp': originalTimestamp,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Check if cache exceeds size limit
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM deduplication_cache'),
    );
    
    if (count != null && count > maxCacheSize) {
      await evictOldest();
    }
  }

  // Remove oldest entries when cache exceeds size limit
  Future<void> evictOldest() async {
    final database = await _db.db;
    final entriesToRemove = maxCacheSize ~/ 10; // Remove 10% of cache
    
    await database.rawDelete('''
      DELETE FROM deduplication_cache
      WHERE message_id IN (
        SELECT message_id FROM deduplication_cache
        ORDER BY seen_timestamp ASC
        LIMIT ?
      )
    ''', [entriesToRemove]);
  }

  // Strictly remove entries whose original timestamp is older than absolute maximum age
  // This guarantees ghost messages cannot loop because they will be actively rejected
  // by MessageManager before even reaching the cache checking phase.
  Future<void> cleanup() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(absoluteMaxAge)
        .millisecondsSinceEpoch;
    
    await database.delete(
      'deduplication_cache',
      where: 'original_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  // Get cache statistics
  Future<Map<String, int>> getStats() async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM deduplication_cache'),
    ) ?? 0;
    
    return {
      'total_entries': count,
      'max_size': maxCacheSize,
    };
  }
}
