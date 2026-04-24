import 'package:sqflite/sqflite.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import 'db_service.dart';

class DeduplicationCache {
  final DBService _db;
  static const int maxCacheSize = DeduplicationLimits.maxCacheSize;

  /// In-memory forwarding fingerprint cache.
  /// Key: "$messageId-$senderId-$hopCount"
  /// Prevents duplicate propagation across different nodes.
  final Set<String> _forwardingFingerprints = {};
  static const int _maxFingerprints = DeduplicationLimits.maxFingerprints;

  /// In-memory forwardedTo tracking per messageId.
  /// Tracks which peers we've already forwarded a specific message to.
  final Map<String, Set<String>> _forwardedTo = {};
  static const int _maxForwardedToEntries =
      DeduplicationLimits.maxForwardedToEntries;

  DeduplicationCache(this._db);

  /// Current number of fingerprints in memory.
  int get size => _forwardingFingerprints.length;

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
    final entriesToRemove = maxCacheSize ~/ DeduplicationLimits.evictionDivisor;

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
  Future<void> cleanup() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(DeduplicationTimerConfig.absoluteMaxAge)
        .millisecondsSinceEpoch;

    await database.delete(
      'deduplication_cache',
      where: 'original_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  // ── Forwarding Fingerprint (Multi-Node Collision Prevention) ──

  /// Check if we've already processed this forwarding fingerprint.
  /// Fingerprint = "$messageId-$senderId-$hopCount"
  bool hasSeenFingerprint(String messageId, String senderId, int hopCount) {
    final key = '$messageId-$senderId-$hopCount';
    if (_forwardingFingerprints.contains(key)) {
      // LRU: touch to move to end
      _forwardingFingerprints.remove(key);
      _forwardingFingerprints.add(key);
      return true;
    }
    return false;
  }

  /// Mark a forwarding fingerprint as seen.
  void markFingerprint(String messageId, String senderId, int hopCount) {
    final key = '$messageId-$senderId-$hopCount';
    _forwardingFingerprints.remove(key);
    _forwardingFingerprints.add(key);

    // Strict boundary enforcement immediately (FIFO/LRU on oldest)
    if (_forwardingFingerprints.length > _maxFingerprints) {
      _forwardingFingerprints.remove(_forwardingFingerprints.first);
    }
  }

  // ── ForwardedTo Tracking (Per-Message Per-Peer Dedup) ──

  /// Check if we've already forwarded this message to a specific peer.
  bool hasForwardedTo(String messageId, String peerId) {
    if (_forwardedTo.containsKey(messageId)) {
      // LRU: touch to move to end
      final peers = _forwardedTo.remove(messageId);
      _forwardedTo[messageId] = peers!;
      return peers.contains(peerId);
    }
    return false;
  }

  /// Mark that we've forwarded this message to a specific peer.
  void markForwardedTo(String messageId, String peerId) {
    if (!_forwardedTo.containsKey(messageId)) {
      _forwardedTo[messageId] = {};
    }
    
    // LRU: move this messageId to the end
    final peers = _forwardedTo.remove(messageId)!;
    peers.add(peerId);
    _forwardedTo[messageId] = peers;

    // Strict boundary enforcement immediately
    if (_forwardedTo.length > _maxForwardedToEntries) {
      _forwardedTo.remove(_forwardedTo.keys.first);
    }
  }

  /// Get count of peers we've forwarded this message to.
  int getForwardCount(String messageId) {
    return _forwardedTo[messageId]?.length ?? 0;
  }

  // Get cache statistics
  Future<Map<String, int>> getStats() async {
    final database = await _db.db;
    final count = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM deduplication_cache'),
        ) ??
        0;

    return {
      'total_entries': count,
      'max_size': maxCacheSize,
      'fingerprints': _forwardingFingerprints.length,
      'forwarded_to_entries': _forwardedTo.length,
    };
  }
}
