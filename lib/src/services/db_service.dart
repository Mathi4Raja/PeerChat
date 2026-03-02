import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/chat_message.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';

class DBService {
  static final DBService _instance = DBService._internal();
  factory DBService() => _instance;
  DBService._internal();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'peerchat.db');
    _db = await openDatabase(
      path,
      version: 17,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        await _ensureCriticalSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateTo2(db);
        }
        if (oldVersion < 3) {
          await _migrateTo3(db);
        }
        if (oldVersion < 4) {
          await _migrateTo4(db);
        }
        if (oldVersion < 5) {
          await _migrateTo5(db);
        }
        if (oldVersion < 6) {
          await _migrateTo6(db);
        }
        if (oldVersion < 7) {
          await _migrateTo7(db);
        }
        if (oldVersion < 8) {
          await _migrateTo8(db);
        }
        if (oldVersion < 9) {
          await _migrateTo9(db);
        }
        if (oldVersion < 10) {
          await _migrateTo10(db);
        }
        if (oldVersion < 11) {
          await _migrateTo11(db);
        }
        if (oldVersion < 12) {
          await _migrateTo12(db);
        }
        if (oldVersion < 13) {
          await _migrateTo13(db);
        }
        if (oldVersion < 14) {
          await _migrateTo14(db);
        }
        if (oldVersion < 15) {
          await _migrateTo15(db);
        }
        if (oldVersion < 16) {
          await _migrateTo16(db);
        }
        if (oldVersion < 17) {
          await _migrateTo17(db);
        }
      },
    );
    return _db!;
  }

  Future<void> _createTables(Database db) async {
    // Existing peers table
    await db.execute('''
      CREATE TABLE peers (
        id TEXT PRIMARY KEY,
        displayName TEXT,
        address TEXT,
        lastSeen INTEGER,
        hasApp INTEGER DEFAULT 0,
        isWiFi INTEGER DEFAULT 0,
        isBluetooth INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        peerId TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        isSentByMe INTEGER NOT NULL,
        status INTEGER NOT NULL,
        isRead INTEGER DEFAULT 1,
        hopCount INTEGER,
        replyToMessageId TEXT,
        replyToContent TEXT,
        replyToPeerId TEXT
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_chat_peer ON chat_messages(peerId, timestamp DESC)');

    // Mesh routing tables
    await db.execute('''
      CREATE TABLE message_queue (
        message_id TEXT PRIMARY KEY,
        next_hop_peer_id TEXT NOT NULL,
        message_data BLOB NOT NULL,
        priority INTEGER NOT NULL,
        queued_timestamp INTEGER NOT NULL,
        origin_type INTEGER NOT NULL DEFAULT 0,
        attempt_count INTEGER DEFAULT 0,
        last_attempt_timestamp INTEGER,
        next_retry_time INTEGER DEFAULT 0,
        expiry_time INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE routes (
        destination_peer_id TEXT PRIMARY KEY,
        next_hop_peer_id TEXT NOT NULL,
        hop_count INTEGER NOT NULL,
        last_used_timestamp INTEGER NOT NULL,
        last_updated_timestamp INTEGER NOT NULL,
        success_count INTEGER DEFAULT 0,
        failure_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE deduplication_cache (
        message_id TEXT PRIMARY KEY,
        seen_timestamp INTEGER NOT NULL,
        original_timestamp INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE blocked_peers (
        peer_id TEXT PRIMARY KEY,
        blocked_until_timestamp INTEGER NOT NULL,
        invalid_signature_count INTEGER NOT NULL
      )
    ''');

    // Create indexes for performance
    await db.execute(
        'CREATE INDEX idx_queue_next_hop ON message_queue(next_hop_peer_id)');
    await db.execute(
        'CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_timestamp ASC)');
    await db.execute(
        'CREATE INDEX idx_routes_next_hop ON routes(next_hop_peer_id)');
    await db.execute(
        'CREATE INDEX idx_dedup_timestamp ON deduplication_cache(seen_timestamp)');

    // Peer public keys table - version 6 has encryption_key
    await db.execute('''
      CREATE TABLE peer_keys (
        peer_id TEXT PRIMARY KEY,
        public_key BLOB NOT NULL,
        encryption_key BLOB,
        added_timestamp INTEGER NOT NULL
      )
    ''');

    // Known WiFi Direct endpoints for auto-reconnection - version 8
    await db.execute('''
      CREATE TABLE known_wifi_endpoints (
        endpoint_id TEXT PRIMARY KEY,
        last_connected_timestamp INTEGER NOT NULL,
        reconnect_attempts INTEGER DEFAULT 0
      )
    ''');

    // File transfer persistent state - version 11
    await db.execute('''
      CREATE TABLE file_transfers (
        file_id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        sha256_hash BLOB NOT NULL,
        total_chunks INTEGER NOT NULL,
        received_chunks INTEGER DEFAULT 0,
        direction INTEGER NOT NULL,
        state INTEGER NOT NULL,
        file_path TEXT,
        ack_timeout_ms INTEGER,
        last_activity INTEGER NOT NULL,
        start_timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE broadcast_messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        signature BLOB NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_broadcast_timestamp ON broadcast_messages(timestamp DESC)');
  }

  Future<void> _migrateTo6(Database db) async {
    // Add encryption_key column to peer_keys table
    await db.execute('ALTER TABLE peer_keys ADD COLUMN encryption_key BLOB');
  }

  Future<void> _migrateTo7(Database db) async {
    // Add isRead column to chat_messages table
    // Default to 1 (read) for existing messages
    await db.execute(
        'ALTER TABLE chat_messages ADD COLUMN isRead INTEGER DEFAULT 1');

    // Add isWiFi and isBluetooth columns to peers table (from user's previous manual setup)
    // We check if they exist or just try to add them if they were supposed to be in v7
    try {
      await db.execute('ALTER TABLE peers ADD COLUMN isWiFi INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute(
          'ALTER TABLE peers ADD COLUMN isBluetooth INTEGER DEFAULT 0');
    } catch (_) {}
  }

  Future<void> _migrateTo8(Database db) async {
    // Add known_wifi_endpoints table for auto-reconnection
    await db.execute('''
      CREATE TABLE known_wifi_endpoints (
        endpoint_id TEXT PRIMARY KEY,
        last_connected_timestamp INTEGER NOT NULL,
        reconnect_attempts INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _migrateTo9(Database db) async {
    // Add original_timestamp to deduplication_cache to fix looping bug
    await db.execute(
        'ALTER TABLE deduplication_cache ADD COLUMN original_timestamp INTEGER DEFAULT 0');
    // For old entries, just set original_timestamp to seen_timestamp
    await db.execute(
        'UPDATE deduplication_cache SET original_timestamp = seen_timestamp WHERE original_timestamp = 0');
  }

  Future<void> _migrateTo11(Database db) async {
    // Add file_transfers table for state persistence
    await db.execute('''
      CREATE TABLE file_transfers (
        file_id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        sha256_hash BLOB NOT NULL,
        total_chunks INTEGER NOT NULL,
        received_chunks INTEGER DEFAULT 0,
        direction INTEGER NOT NULL,
        state INTEGER NOT NULL,
        file_path TEXT,
        ack_timeout_ms INTEGER,
        last_activity INTEGER NOT NULL,
        start_timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateTo12(Database db) async {
    await db.execute('''
      CREATE TABLE broadcast_messages (
        id TEXT PRIMARY KEY,
        sender_id TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        signature BLOB NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_broadcast_timestamp ON broadcast_messages(timestamp DESC)');
    // Ensure dedup column exists even on previously inconsistent schemas.
    try {
      await db.execute(
          'ALTER TABLE deduplication_cache ADD COLUMN original_timestamp INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute(
          'UPDATE deduplication_cache SET original_timestamp = seen_timestamp WHERE original_timestamp = 0');
    } catch (_) {}
  }

  Future<void> _migrateTo13(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE message_queue ADD COLUMN expiry_time INTEGER DEFAULT 0');
    } catch (_) {}
  }

  Future<void> _migrateTo14(Database db) async {
    try {
      await db.execute('ALTER TABLE chat_messages ADD COLUMN hopCount INTEGER');
    } catch (_) {}
  }

  Future<void> _migrateTo15(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE message_queue ADD COLUMN origin_type INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}
  }

  Future<void> _migrateTo16(Database db) async {
    await db.execute('DROP TABLE IF EXISTS pending_acks');
  }

  Future<void> _migrateTo17(Database db) async {
    try {
      await db.execute(
          'ALTER TABLE chat_messages ADD COLUMN replyToMessageId TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE chat_messages ADD COLUMN replyToContent TEXT');
    } catch (_) {}
    try {
      await db
          .execute('ALTER TABLE chat_messages ADD COLUMN replyToPeerId TEXT');
    } catch (_) {}
  }

  Future<void> _ensureCriticalSchema(Database db) async {
    final dedupHasOriginalTs =
        await _hasColumn(db, 'deduplication_cache', 'original_timestamp');
    if (!dedupHasOriginalTs) {
      await db.execute(
          'ALTER TABLE deduplication_cache ADD COLUMN original_timestamp INTEGER DEFAULT 0');
      await db.execute(
          'UPDATE deduplication_cache SET original_timestamp = seen_timestamp WHERE original_timestamp = 0');
    }

    final chatHasHopCount = await _hasColumn(db, 'chat_messages', 'hopCount');
    if (!chatHasHopCount) {
      await db.execute('ALTER TABLE chat_messages ADD COLUMN hopCount INTEGER');
    }
    final chatHasReplyToMessageId =
        await _hasColumn(db, 'chat_messages', 'replyToMessageId');
    if (!chatHasReplyToMessageId) {
      await db.execute(
          'ALTER TABLE chat_messages ADD COLUMN replyToMessageId TEXT');
    }
    final chatHasReplyToContent =
        await _hasColumn(db, 'chat_messages', 'replyToContent');
    if (!chatHasReplyToContent) {
      await db
          .execute('ALTER TABLE chat_messages ADD COLUMN replyToContent TEXT');
    }
    final chatHasReplyToPeerId =
        await _hasColumn(db, 'chat_messages', 'replyToPeerId');
    if (!chatHasReplyToPeerId) {
      await db
          .execute('ALTER TABLE chat_messages ADD COLUMN replyToPeerId TEXT');
    }

    final queueHasOrigin = await _hasColumn(db, 'message_queue', 'origin_type');
    if (!queueHasOrigin) {
      await db.execute(
          'ALTER TABLE message_queue ADD COLUMN origin_type INTEGER NOT NULL DEFAULT 0');
    }

    // Remove obsolete delivery-ACK table from older installations.
    await db.execute('DROP TABLE IF EXISTS pending_acks');
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final row in rows) {
      if ((row['name'] as String?) == column) {
        return true;
      }
    }
    return false;
  }

  Future<void> _migrateTo10(Database db) async {
    // Add next_retry_time column for exponential backoff
    await db.execute(
        'ALTER TABLE message_queue ADD COLUMN next_retry_time INTEGER DEFAULT 0');
  }

  Future<void> _migrateTo2(Database db) async {
    // Add mesh routing tables for existing databases
    await db.execute('''
      CREATE TABLE message_queue (
        message_id TEXT PRIMARY KEY,
        next_hop_peer_id TEXT NOT NULL,
        message_data BLOB NOT NULL,
        priority INTEGER NOT NULL,
        queued_timestamp INTEGER NOT NULL,
        attempt_count INTEGER DEFAULT 0,
        last_attempt_timestamp INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE routes (
        destination_peer_id TEXT PRIMARY KEY,
        next_hop_peer_id TEXT NOT NULL,
        hop_count INTEGER NOT NULL,
        last_used_timestamp INTEGER NOT NULL,
        last_updated_timestamp INTEGER NOT NULL,
        success_count INTEGER DEFAULT 0,
        failure_count INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE deduplication_cache (
        message_id TEXT PRIMARY KEY,
        seen_timestamp INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE blocked_peers (
        peer_id TEXT PRIMARY KEY,
        blocked_until_timestamp INTEGER NOT NULL,
        invalid_signature_count INTEGER NOT NULL
      )
    ''');

    // Create indexes
    await db.execute(
        'CREATE INDEX idx_queue_next_hop ON message_queue(next_hop_peer_id)');
    await db.execute(
        'CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_timestamp ASC)');
    await db.execute(
        'CREATE INDEX idx_routes_next_hop ON routes(next_hop_peer_id)');
    await db.execute(
        'CREATE INDEX idx_dedup_timestamp ON deduplication_cache(seen_timestamp)');
  }

  Future<void> _migrateTo3(Database db) async {
    // Add hasApp column to peers table
    await db.execute('ALTER TABLE peers ADD COLUMN hasApp INTEGER DEFAULT 0');
  }

  Future<void> _migrateTo4(Database db) async {
    // Add chat_messages table
    await db.execute('''
      CREATE TABLE chat_messages (
        id TEXT PRIMARY KEY,
        peerId TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        isSentByMe INTEGER NOT NULL,
        status INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_chat_peer ON chat_messages(peerId, timestamp DESC)');
  }

  Future<void> _migrateTo5(Database db) async {
    // Add peer_keys table
    await db.execute('''
      CREATE TABLE peer_keys (
        peer_id TEXT PRIMARY KEY,
        public_key BLOB NOT NULL,
        added_timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future<void> upsertPeer(Peer p) async {
    final d = await db;

    // Check if peer already exists to merge discovery flags
    final List<Map<String, dynamic>> existing = await d.query(
      'peers',
      where: 'id = ?',
      whereArgs: [p.id],
    );

    if (existing.isNotEmpty) {
      final oldPeer = Peer.fromMap(existing.first);
      // Merge flags: if either was true, it remains true
      final mergedPeer = Peer(
        id: p.id,
        displayName: p.displayName != 'Unknown Device'
            ? p.displayName
            : oldPeer.displayName,
        address: p.address,
        lastSeen: p.lastSeen,
        hasApp: p.hasApp || oldPeer.hasApp,
        isWiFi: p.isWiFi || oldPeer.isWiFi,
        isBluetooth: p.isBluetooth || oldPeer.isBluetooth,
      );
      await d.insert('peers', mergedPeer.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await d.insert('peers', p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> deletePeer(String peerId) async {
    final d = await db;
    await d.delete('peers', where: 'id = ?', whereArgs: [peerId]);
  }

  Future<List<Peer>> allPeers() async {
    final d = await db;
    final rows = await d.query('peers');
    return rows.map((r) => Peer.fromMap(r)).toList();
  }

  // Chat message operations
  Future<void> insertChatMessage(ChatMessage message) async {
    final d = await db;
    await d.insert('chat_messages', message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatMessage>> getChatMessages(String peerId) async {
    final d = await db;
    final rows = await d.query(
      'chat_messages',
      where: 'peerId = ?',
      whereArgs: [peerId],
      orderBy: 'timestamp ASC, id ASC',
    );
    return rows.map((r) => ChatMessage.fromMap(r)).toList();
  }

  Future<ChatMessage?> getChatMessageById(String messageId) async {
    final d = await db;
    final rows = await d.query(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  Future<Map<String, ChatMessage>> getChatMessagesByIds(
      List<String> messageIds) async {
    if (messageIds.isEmpty) return {};
    final d = await db;
    final placeholders = List.filled(messageIds.length, '?').join(',');
    final rows = await d.query(
      'chat_messages',
      where: 'id IN ($placeholders)',
      whereArgs: messageIds,
    );
    final map = <String, ChatMessage>{};
    for (final row in rows) {
      final message = ChatMessage.fromMap(row);
      map[message.id] = message;
    }
    return map;
  }

  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status, {
    int? hopCount,
    bool clearHopCount = false,
  }) async {
    final d = await db;
    final values = <String, Object?>{
      'status': status.index,
    };
    if (hopCount != null) {
      values['hopCount'] = hopCount;
    } else if (clearHopCount) {
      values['hopCount'] = null;
    }
    await d.update(
      'chat_messages',
      values,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  // Peer public key operations
  Future<void> savePeerKeys({
    required String peerId,
    required Uint8List signingKey,
    required Uint8List encryptionKey,
  }) async {
    final d = await db;
    await d.insert(
      'peer_keys',
      {
        'peer_id': peerId,
        'public_key': signingKey,
        'encryption_key': encryptionKey,
        'added_timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> savePeerPublicKey(String peerId, Uint8List publicKey) async {
    final d = await db;
    await d.insert(
      'peer_keys',
      {
        'peer_id': peerId,
        'public_key': publicKey,
        'added_timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Uint8List?> getPeerPublicKey(String peerId) async {
    final d = await db;
    final rows = await d.query(
      'peer_keys',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
    if (rows.isEmpty) return null;
    return rows.first['public_key'] as Uint8List?;
  }

  Future<Uint8List?> getPeerEncryptionKey(String peerId) async {
    final d = await db;
    final rows = await d.query(
      'peer_keys',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );
    if (rows.isEmpty) return null;
    return rows.first['encryption_key'] as Uint8List?;
  }

  Future<Map<String, int>> getUnreadMessageCounts() async {
    final d = await db;
    final List<Map<String, dynamic>> results = await d.rawQuery('''
      SELECT peerId, COUNT(*) as count 
      FROM chat_messages 
      WHERE isRead = 0 AND isSentByMe = 0
      GROUP BY peerId
    ''');

    final Map<String, int> counts = {};
    for (final row in results) {
      counts[row['peerId'] as String] = row['count'] as int;
    }
    return counts;
  }

  Future<List<String>> getUnreadMessageIds(String peerId) async {
    final d = await db;
    final List<Map<String, dynamic>> results = await d.query(
      'chat_messages',
      columns: ['id'],
      where: 'peerId = ? AND isRead = 0 AND isSentByMe = 0',
      whereArgs: [peerId],
    );
    return results.map((row) => row['id'] as String).toList();
  }

  Future<void> markMessagesAsRead(String peerId) async {
    final d = await db;
    await d.update(
      'chat_messages',
      {'isRead': 1},
      where: 'peerId = ? AND isRead = 0',
      whereArgs: [peerId],
    );
  }

  /// Returns one row per peer with the most recent chat message.
  ///
  /// Row keys:
  /// - peer_id
  /// - last_content
  /// - last_timestamp
  /// - is_sent_by_me
  /// - last_status
  /// - display_name
  /// - address
  /// - last_seen
  /// - has_app
  /// - is_wifi
  /// - is_bluetooth
  Future<List<Map<String, Object?>>> getRecentChatRows() async {
    final d = await db;
    final latestByPeer = await d.rawQuery('''
      SELECT
        peerId AS peer_id,
        MAX(timestamp) AS last_timestamp
      FROM chat_messages
      GROUP BY peerId
      ORDER BY last_timestamp DESC
    ''');

    final rows = <Map<String, Object?>>[];
    for (final row in latestByPeer) {
      final peerId = row['peer_id'] as String?;
      if (peerId == null || peerId.isEmpty) continue;

      final latestMessageRows = await d.query(
        'chat_messages',
        columns: ['content', 'timestamp', 'isSentByMe', 'status'],
        where: 'peerId = ?',
        whereArgs: [peerId],
        orderBy: 'timestamp DESC, id DESC',
        limit: 1,
      );
      if (latestMessageRows.isEmpty) continue;
      final message = latestMessageRows.first;

      final peerRows = await d.query(
        'peers',
        columns: [
          'displayName',
          'address',
          'lastSeen',
          'hasApp',
          'isWiFi',
          'isBluetooth'
        ],
        where: 'id = ?',
        whereArgs: [peerId],
        limit: 1,
      );
      final peer =
          peerRows.isNotEmpty ? peerRows.first : const <String, Object?>{};

      rows.add({
        'peer_id': peerId,
        'last_content': message['content'],
        'last_timestamp': message['timestamp'],
        'is_sent_by_me': message['isSentByMe'],
        'last_status': message['status'],
        'display_name': peer['displayName'],
        'address': peer['address'],
        'last_seen': peer['lastSeen'],
        'has_app': peer['hasApp'],
        'is_wifi': peer['isWiFi'],
        'is_bluetooth': peer['isBluetooth'],
      });
    }

    return rows;
  }

  /// Deletes all local chat messages with a peer.
  Future<void> deleteChatConversation(String peerId) async {
    final d = await db;
    await d.transaction((txn) async {
      await txn.delete(
        'chat_messages',
        where: 'peerId = ?',
        whereArgs: [peerId],
      );
    });
  }

  /// Get latest emergency broadcast messages (newest first).
  Future<List<Map<String, Object?>>> getBroadcastMessages({
    int limit = BroadcastLimits.defaultQueryLimit,
  }) async {
    final d = await db;
    final rows = await d.query(
      'broadcast_messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.cast<Map<String, Object?>>();
  }

  /// Purge broadcast messages older than [maxAge].
  Future<int> purgeOldBroadcastMessages({
    Duration maxAge = DatabaseTimerConfig.defaultBroadcastMaxAge,
  }) async {
    final d = await db;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - maxAge.inMilliseconds;
    return d.delete(
      'broadcast_messages',
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  // Known WiFi Direct endpoints operations
  Future<void> saveKnownWiFiEndpoint(String endpointId) async {
    final d = await db;
    await d.insert(
      'known_wifi_endpoints',
      {
        'endpoint_id': endpointId,
        'last_connected_timestamp': DateTime.now().millisecondsSinceEpoch,
        'reconnect_attempts': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> getKnownWiFiEndpoints() async {
    final d = await db;
    final rows = await d.query('known_wifi_endpoints');
    return rows.map((r) => r['endpoint_id'] as String).toSet();
  }

  Future<int> getReconnectAttempts(String endpointId) async {
    final d = await db;
    final rows = await d.query(
      'known_wifi_endpoints',
      where: 'endpoint_id = ?',
      whereArgs: [endpointId],
    );
    if (rows.isEmpty) return 0;
    return rows.first['reconnect_attempts'] as int;
  }

  Future<void> incrementReconnectAttempts(String endpointId) async {
    final d = await db;
    await d.rawUpdate(
      'UPDATE known_wifi_endpoints SET reconnect_attempts = reconnect_attempts + 1 WHERE endpoint_id = ?',
      [endpointId],
    );
  }

  Future<void> resetReconnectAttempts(String endpointId) async {
    final d = await db;
    await d.update(
      'known_wifi_endpoints',
      {
        'reconnect_attempts': 0,
        'last_connected_timestamp': DateTime.now().millisecondsSinceEpoch
      },
      where: 'endpoint_id = ?',
      whereArgs: [endpointId],
    );
  }

  Future<void> removeKnownWiFiEndpoint(String endpointId) async {
    final d = await db;
    await d.delete(
      'known_wifi_endpoints',
      where: 'endpoint_id = ?',
      whereArgs: [endpointId],
    );
  }

  /// Remove stale network artifacts to keep discovery/routing state healthy.
  ///
  /// Returns counts for removed records.
  Future<Map<String, int>> cleanupStaleNetworkData({
    Duration stalePeerAge = DatabaseTimerConfig.stalePeerAge,
    Duration staleRouteAge = DatabaseTimerConfig.staleRouteAge,
    Duration staleEndpointAge = DatabaseTimerConfig.staleEndpointAge,
    List<String> preservePeerIds = const [],
  }) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final peerCutoff = now - stalePeerAge.inMilliseconds;
    final routeCutoff = now - staleRouteAge.inMilliseconds;
    final endpointCutoff = now - staleEndpointAge.inMilliseconds;

    String stalePeerWhere = 'lastSeen < ?';
    final stalePeerArgs = <Object?>[peerCutoff];
    if (preservePeerIds.isNotEmpty) {
      final placeholders = List.filled(preservePeerIds.length, '?').join(',');
      stalePeerWhere += ' AND id NOT IN ($placeholders)';
      stalePeerArgs.addAll(preservePeerIds);
    }

    final stalePeerRows = await d.query(
      'peers',
      columns: ['id'],
      where: stalePeerWhere,
      whereArgs: stalePeerArgs,
    );
    final stalePeerIds = stalePeerRows
        .map((row) => row['id'] as String?)
        .whereType<String>()
        .toList();

    int removedRoutesViaStalePeers = 0;
    int removedQueueViaStalePeers = 0;
    if (stalePeerIds.isNotEmpty) {
      final placeholders = List.filled(stalePeerIds.length, '?').join(',');

      removedRoutesViaStalePeers = await d.rawDelete(
        '''
        DELETE FROM routes
        WHERE destination_peer_id IN ($placeholders)
           OR next_hop_peer_id IN ($placeholders)
        ''',
        [...stalePeerIds, ...stalePeerIds],
      );

      removedQueueViaStalePeers = await d.rawDelete(
        'DELETE FROM message_queue WHERE next_hop_peer_id IN ($placeholders)',
        stalePeerIds,
      );
    }

    final removedPeers = await d.delete(
      'peers',
      where: stalePeerWhere,
      whereArgs: stalePeerArgs,
    );

    final removedRoutesByAge = await d.delete(
      'routes',
      where: 'last_updated_timestamp < ? AND last_used_timestamp < ?',
      whereArgs: [routeCutoff, routeCutoff],
    );

    final removedEndpoints = await d.delete(
      'known_wifi_endpoints',
      where: 'last_connected_timestamp < ?',
      whereArgs: [endpointCutoff],
    );

    return {
      'removed_peers': removedPeers,
      'removed_routes_by_age': removedRoutesByAge,
      'removed_routes_via_stale_peers': removedRoutesViaStalePeers,
      'removed_queue_via_stale_peers': removedQueueViaStalePeers,
      'removed_known_endpoints': removedEndpoints,
    };
  }
}
