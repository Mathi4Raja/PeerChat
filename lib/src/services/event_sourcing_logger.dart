import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:collection';
import '../config/limits_config.dart';
import '../utils/distributed_tracer.dart';
import 'db_service.dart';

class EventSourcingLogger {
  static final EventSourcingLogger _instance = EventSourcingLogger._internal();
  factory EventSourcingLogger() => _instance;
  EventSourcingLogger._internal();

  DBService? _dbService;
  final _uuid = const Uuid();
  
  final Queue<Map<String, dynamic>> _writeBuffer = Queue();
  bool _isFlushing = false;
  static const int _maxBufferSize = 1000;
  static const int _flushThreshold = 50;
  static const Duration _flushInterval = Duration(milliseconds: 500);
  Timer? _flushTimer;

  void initialize(DBService dbService) {
    _dbService = dbService;
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flushBuffer());
  }

  /// Write an event asynchronously. Backpressure applied if buffer is full.
  void logEvent({
    required String entityId,
    required String eventType,
    required Map<String, dynamic> payload,
    String? correlationId,
  }) {
    if (_dbService == null) {
      debugPrint('EventSourcingLogger not initialized');
      return;
    }

    if (_writeBuffer.length >= _maxBufferSize) {
      // Apply backpressure: drop oldest (low priority) log or ignore current. 
      // For logging, we drop the oldest to keep the latest state history.
      _writeBuffer.removeFirst();
    }

    final eventId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Auto-correlate if a span is active in DistributedTracer context
    // This is a naive heuristic if no explicit correlation provided.
    final effectiveCorrelationId = correlationId ?? entityId; 

    final eventRecord = {
      'event_id': eventId,
      'timestamp': now,
      'entity_id': entityId,
      'event_type': eventType,
      'payload': jsonEncode(payload),
      'correlation_id': effectiveCorrelationId,
    };

    _writeBuffer.add(eventRecord);

    if (_writeBuffer.length >= _flushThreshold && !_isFlushing) {
      _flushBuffer();
    }
  }

  Future<void> _flushBuffer() async {
    if (_isFlushing || _writeBuffer.isEmpty || _dbService == null) return;
    
    _isFlushing = true;
    try {
      final db = await _dbService!.db;
      final batch = db.batch();
      
      int processed = 0;
      while (_writeBuffer.isNotEmpty && processed < 200) {
        final record = _writeBuffer.removeFirst();
        batch.insert('event_log', record, conflictAlgorithm: ConflictAlgorithm.replace);
        processed++;
      }
      
      await batch.commit(noResult: true);
      
      // Enforce TTL/Size asynchronously occasionally
      if (DateTime.now().millisecond % 10 == 0) {
        _enforceRetentionPolicy(db);
      }
    } catch (e) {
      debugPrint('EventSourcingLogger flush error: $e');
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> _enforceRetentionPolicy(Database db) async {
    // Keep max 10,000 events or based on TTL.
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM event_log')
    ) ?? 0;
    
    if (count > 10000) {
      final excess = count - 10000;
      await db.rawDelete('''
        DELETE FROM event_log 
        WHERE event_id IN (
          SELECT event_id FROM event_log 
          ORDER BY timestamp ASC 
          LIMIT ?
        )
      ''', [excess]);
    }
  }

  /// Retrieves events for a specific entity to reconstruct state
  Future<List<Map<String, dynamic>>> getEventsForEntity(String entityId) async {
    if (_dbService == null) return [];
    final db = await _dbService!.db;
    return await db.query(
      'event_log',
      where: 'entity_id = ?',
      whereArgs: [entityId],
      orderBy: 'timestamp ASC',
    );
  }
}
