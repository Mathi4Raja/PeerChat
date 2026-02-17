import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/chat_message.dart';

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
      version: 7,
      onCreate: (db, version) async {
        await _createTables(db);
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
        isRead INTEGER DEFAULT 1
      )
    ''');
    
    await db.execute('CREATE INDEX idx_chat_peer ON chat_messages(peerId, timestamp DESC)');

    // Mesh routing tables
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

    await db.execute('''
      CREATE TABLE pending_acks (
        message_id TEXT PRIMARY KEY,
        recipient_peer_id TEXT NOT NULL,
        sent_timestamp INTEGER NOT NULL
      )
    ''');

    // Create indexes for performance
    await db.execute('CREATE INDEX idx_queue_next_hop ON message_queue(next_hop_peer_id)');
    await db.execute('CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_timestamp ASC)');
    await db.execute('CREATE INDEX idx_routes_next_hop ON routes(next_hop_peer_id)');
    await db.execute('CREATE INDEX idx_dedup_timestamp ON deduplication_cache(seen_timestamp)');
    
    // Peer public keys table - version 6 has encryption_key
    await db.execute('''
      CREATE TABLE peer_keys (
        peer_id TEXT PRIMARY KEY,
        public_key BLOB NOT NULL,
        encryption_key BLOB,
        added_timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _migrateTo6(Database db) async {
    // Add encryption_key column to peer_keys table
    await db.execute('ALTER TABLE peer_keys ADD COLUMN encryption_key BLOB');
  }

  Future<void> _migrateTo7(Database db) async {
    // Add isRead column to chat_messages table
    // Default to 1 (read) for existing messages
    await db.execute('ALTER TABLE chat_messages ADD COLUMN isRead INTEGER DEFAULT 1');
    
    // Add isWiFi and isBluetooth columns to peers table (from user's previous manual setup)
    // We check if they exist or just try to add them if they were supposed to be in v7
    try {
      await db.execute('ALTER TABLE peers ADD COLUMN isWiFi INTEGER DEFAULT 0');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE peers ADD COLUMN isBluetooth INTEGER DEFAULT 0');
    } catch (_) {}
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

    await db.execute('''
      CREATE TABLE pending_acks (
        message_id TEXT PRIMARY KEY,
        recipient_peer_id TEXT NOT NULL,
        sent_timestamp INTEGER NOT NULL
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_queue_next_hop ON message_queue(next_hop_peer_id)');
    await db.execute('CREATE INDEX idx_queue_priority ON message_queue(priority DESC, queued_timestamp ASC)');
    await db.execute('CREATE INDEX idx_routes_next_hop ON routes(next_hop_peer_id)');
    await db.execute('CREATE INDEX idx_dedup_timestamp ON deduplication_cache(seen_timestamp)');
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
    await db.execute('CREATE INDEX idx_chat_peer ON chat_messages(peerId, timestamp DESC)');
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
        displayName: p.displayName != 'Unknown Device' ? p.displayName : oldPeer.displayName,
        address: p.address,
        lastSeen: p.lastSeen,
        hasApp: p.hasApp || oldPeer.hasApp,
        isWiFi: p.isWiFi || oldPeer.isWiFi,
        isBluetooth: p.isBluetooth || oldPeer.isBluetooth,
      );
      await d.insert('peers', mergedPeer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    } else {
      await d.insert('peers', p.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
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
    await d.insert('chat_messages', message.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  
  Future<List<ChatMessage>> getChatMessages(String peerId) async {
    final d = await db;
    final rows = await d.query(
      'chat_messages',
      where: 'peerId = ?',
      whereArgs: [peerId],
      orderBy: 'timestamp ASC',
    );
    return rows.map((r) => ChatMessage.fromMap(r)).toList();
  }
  
  Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final d = await db;
    await d.update(
      'chat_messages',
      {'status': status.index},
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
}
