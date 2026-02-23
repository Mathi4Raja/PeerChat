import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/file_transfer.dart';
import 'db_service.dart';
import 'transport_service.dart';
import 'connection_manager.dart';

/// Service for handling P2P file transfers with:
/// - 64KB chunking + sliding window (5 in-flight)
/// - Cumulative ACK (highestContiguousChunkIndex)
/// - Chunk ACK timeout (10s WiFi / 15s BT)
/// - BitSet chunk ordering (never assumes ordered delivery)
/// - SHA-256 integrity validation
/// - Crash recovery (resumeIncompleteTransfers)
/// - Disk pressure check before accepting transfers
/// - Temp file cleanup on start
class FileTransferService extends ChangeNotifier {
  final DBService _db;
  final MultiTransportService _transportService;
  final ConnectionManager _connectionManager;

  /// Active transfers keyed by fileId.
  final Map<String, FileTransferSession> _transfers = {};

  /// Pending incoming transfer requests (waiting for user acceptance).
  final Map<String, FileTransferSession> _pendingIncoming = {};

  /// Stream for notifying UI of transfer updates.
  final StreamController<FileTransferSession> _transferUpdateController =
      StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onTransferUpdate => _transferUpdateController.stream;

  /// Stream for incoming transfer requests (UI shows accept/reject dialog).
  final StreamController<FileTransferSession> _incomingRequestController =
      StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onIncomingRequest => _incomingRequestController.stream;

  /// ACK timeout timers per file transfer.
  final Map<String, Timer> _ackTimers = {};

  /// Stale transfer cleanup interval.
  static const Duration staleThreshold = Duration(minutes: 10);

  /// Temp file max age for cleanup.
  static const Duration tempFileMaxAge = Duration(hours: 24);

  FileTransferService(this._db, this._transportService, this._connectionManager);

  /// Initialize the service: clean up old temp files, resume incomplete transfers.
  Future<void> init() async {
    await _cleanupTempFiles();
    await _resumeIncompleteTransfers();
  }

  /// Get all active transfers.
  List<FileTransferSession> get activeTransfers => _transfers.values.toList();

  /// Get pending incoming requests.
  List<FileTransferSession> get pendingRequests => _pendingIncoming.values.toList();

  // ── SENDER FLOW ──

  /// Initiate a file transfer to a directly connected peer.
  Future<FileTransferSession?> sendFile({
    required String peerId,
    required String filePath,
    String? mimeType,
  }) async {
    // Verify peer is directly connected
    final transportId = _connectionManager.getTransportId(peerId);
    if (transportId == null) {
      debugPrint('FileTransfer: Cannot send — peer $peerId not directly connected');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('FileTransfer: File not found: $filePath');
      return null;
    }

    final fileSize = await file.length();
    final fileName = filePath.split(Platform.pathSeparator).last;
    final fileId = '${peerId.substring(0, 8)}_${const Uuid().v4()}';

    // Compute SHA-256 hash
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes);

    final totalChunks = (fileSize / FileMetadata.chunkSize).ceil();

    final metadata = FileMetadata(
      fileId: fileId,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType ?? 'application/octet-stream',
      sha256Hash: Uint8List.fromList(hash.bytes),
      totalChunks: totalChunks,
    );

    final session = FileTransferSession(
      fileId: fileId,
      peerId: peerId,
      metadata: metadata,
      direction: TransferDirection.sending,
      filePath: filePath,
    );

    _transfers[fileId] = session;

    // Send FILE_META message
    await _sendFileTransferMessage(
      peerId: peerId,
      type: FileTransferMessageType.fileMeta,
      fileId: fileId,
      data: _encodeMetadata(metadata),
    );

    debugPrint('FileTransfer: Initiated send of "$fileName" ($totalChunks chunks) to $peerId');
    _transferUpdateController.add(session);
    notifyListeners();
    return session;
  }

  // ── RECEIVER FLOW ──

  /// Handle incoming file transfer protocol message.
  Future<void> handleFileTransferMessage({
    required String fromPeerId,
    required FileTransferMessageType type,
    required String fileId,
    required Uint8List data,
  }) async {
    switch (type) {
      case FileTransferMessageType.fileMeta:
        await _handleFileMeta(fromPeerId, fileId, data);
        break;
      case FileTransferMessageType.fileAccept:
        await _handleFileAccept(fileId);
        break;
      case FileTransferMessageType.fileReject:
        _handleFileReject(fileId);
        break;
      case FileTransferMessageType.chunk:
        await _handleChunk(fromPeerId, fileId, data);
        break;
      case FileTransferMessageType.chunkAck:
        await _handleChunkAck(fileId, data);
        break;
      case FileTransferMessageType.fileComplete:
        _handleFileComplete(fileId);
        break;
      case FileTransferMessageType.resumeFrom:
        await _handleResumeFrom(fileId, data);
        break;
      case FileTransferMessageType.cancelTransfer:
        _handleCancel(fileId);
        break;
    }
  }

  /// Accept a pending incoming transfer.
  Future<void> acceptTransfer(String fileId) async {
    final session = _pendingIncoming.remove(fileId);
    if (session == null) return;

    // Disk pressure check
    final available = await _getAvailableStorage();
    final required = session.metadata.fileSize;
    if (available < required * 1.2) {
      debugPrint('FileTransfer: Insufficient storage. Available: $available, Required: $required');
      session.state = FileTransferState.failed;
      await _sendFileTransferMessage(
        peerId: session.peerId,
        type: FileTransferMessageType.fileReject,
        fileId: fileId,
        data: utf8.encode('INSUFFICIENT_STORAGE'),
      );
      _transferUpdateController.add(session);
      notifyListeners();
      return;
    }

    // Create temp file
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/peerchat_transfer_$fileId.tmp';
    session.filePath = tempPath;
    session.state = FileTransferState.transferring;
    _transfers[fileId] = session;

    // Persist transfer state for crash recovery
    await _persistTransferState(session);

    // Send acceptance
    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.fileAccept,
      fileId: fileId,
      data: Uint8List(0),
    );

    debugPrint('FileTransfer: Accepted transfer $fileId');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  /// Reject a pending incoming transfer.
  Future<void> rejectTransfer(String fileId) async {
    final session = _pendingIncoming.remove(fileId);
    if (session == null) return;

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.fileReject,
      fileId: fileId,
      data: Uint8List(0),
    );

    debugPrint('FileTransfer: Rejected transfer $fileId');
    notifyListeners();
  }

  /// Cancel an active transfer.
  Future<void> cancelTransfer(String fileId) async {
    final session = _transfers.remove(fileId);
    if (session == null) return;

    session.state = FileTransferState.cancelled;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.cancelTransfer,
      fileId: fileId,
      data: Uint8List(0),
    );

    // Clean up temp file
    if (session.direction == TransferDirection.receiving && session.filePath != null) {
      final tempFile = File(session.filePath!);
      if (await tempFile.exists()) await tempFile.delete();
    }

    await _removeTransferState(fileId);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  // ── INTERNAL HANDLERS ──

  Future<void> _handleFileMeta(String fromPeerId, String fileId, Uint8List data) async {
    final metadata = _decodeMetadata(data);
    if (metadata == null) return;

    final session = FileTransferSession(
      fileId: fileId,
      peerId: fromPeerId,
      metadata: metadata,
      direction: TransferDirection.receiving,
    );

    _pendingIncoming[fileId] = session;
    _incomingRequestController.add(session);
    debugPrint('FileTransfer: Incoming request — "${metadata.fileName}" (${metadata.fileSize} bytes)');
    notifyListeners();
  }

  Future<void> _handleFileAccept(String fileId) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) return;

    session.state = FileTransferState.transferring;
    debugPrint('FileTransfer: Peer accepted transfer $fileId, starting chunk stream');

    // Start sending chunks
    await _sendNextChunks(session);
    _startAckTimer(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  void _handleFileReject(String fileId) {
    final session = _transfers.remove(fileId);
    if (session == null) return;

    session.state = FileTransferState.failed;
    debugPrint('FileTransfer: Peer rejected transfer $fileId');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleChunk(String fromPeerId, String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.receiving) return;

    // Parse chunk: first 4 bytes = index, rest = data
    if (data.length < 4) return;
    final chunkIndex = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    final chunkData = data.sublist(4);

    // Skip if already received (dedup)
    if (session.chunkTracker.isReceived(chunkIndex)) return;

    // Write chunk to temp file at correct offset
    if (session.filePath != null) {
      final file = File(session.filePath!);
      final raf = await file.open(mode: FileMode.writeOnlyAppend);
      try {
        await raf.setPosition(chunkIndex * FileMetadata.chunkSize);
        await raf.writeFrom(chunkData);
      } finally {
        await raf.close();
      }
    }

    session.chunkTracker.markReceived(chunkIndex);
    session.lastActivityTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Send cumulative ACK
    final highestContiguous = session.chunkTracker.highestContiguous;
    final ackData = Uint8List(4)
      ..[0] = (highestContiguous >> 24) & 0xFF
      ..[1] = (highestContiguous >> 16) & 0xFF
      ..[2] = (highestContiguous >> 8) & 0xFF
      ..[3] = highestContiguous & 0xFF;

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.chunkAck,
      fileId: fileId,
      data: ackData,
    );

    // Check if complete
    if (session.chunkTracker.isComplete) {
      await _verifyAndComplete(session);
    }

    // Update persist state periodically (every 10 chunks)
    if (session.chunkTracker.receivedCount % 10 == 0) {
      await _persistTransferState(session);
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleChunkAck(String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) return;

    if (data.length < 4) return;
    final highestContiguous = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];

    // Mark all chunks up to highestContiguous as received
    for (int i = 0; i <= highestContiguous; i++) {
      session.chunkTracker.markReceived(i);
      session.inFlightChunks.remove(i);
      session.chunkRetryCount.remove(i);
      session.chunkSentTimestamp.remove(i);
    }

    session.lastActivityTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Check if all chunks acknowledged
    if (session.chunkTracker.isComplete) {
      session.state = FileTransferState.completed;
      _ackTimers[fileId]?.cancel();
      _ackTimers.remove(fileId);

      await _sendFileTransferMessage(
        peerId: session.peerId,
        type: FileTransferMessageType.fileComplete,
        fileId: fileId,
        data: Uint8List(0),
      );

      await _removeTransferState(fileId);
      debugPrint('FileTransfer: Send complete for $fileId');
    } else {
      // Send more chunks (fill the window)
      await _sendNextChunks(session);
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  void _handleFileComplete(String fileId) {
    final session = _transfers[fileId];
    if (session == null) return;

    session.state = FileTransferState.completed;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);
    debugPrint('FileTransfer: Transfer $fileId marked complete by peer');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleResumeFrom(String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) return;

    if (data.length < 4) return;
    final resumeIndex = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];

    // Mark all chunks before resumeIndex as received
    for (int i = 0; i < resumeIndex; i++) {
      session.chunkTracker.markReceived(i);
    }

    session.state = FileTransferState.transferring;
    session.inFlightChunks.clear();
    debugPrint('FileTransfer: Resuming $fileId from chunk $resumeIndex');

    await _sendNextChunks(session);
    _startAckTimer(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  void _handleCancel(String fileId) {
    final session = _transfers.remove(fileId) ?? _pendingIncoming.remove(fileId);
    if (session == null) return;

    session.state = FileTransferState.cancelled;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);
    debugPrint('FileTransfer: Transfer $fileId cancelled by peer');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  // ── CHUNK SENDING ──

  Future<void> _sendNextChunks(FileTransferSession session) async {
    if (session.state != FileTransferState.transferring) return;
    if (session.filePath == null) return;

    final file = File(session.filePath!);
    if (!await file.exists()) return;

    while (session.canSendMore) {
      final chunkIndex = session.nextChunkToSend;
      if (chunkIndex == null) break;

      // Read chunk from file
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(chunkIndex * FileMetadata.chunkSize);
        final remaining = session.metadata.fileSize - (chunkIndex * FileMetadata.chunkSize);
        final readSize = remaining < FileMetadata.chunkSize ? remaining : FileMetadata.chunkSize;
        final chunkData = await raf.read(readSize);

        // Prepend chunk index (4 bytes)
        final payload = BytesBuilder();
        payload.add(Uint8List(4)
          ..[0] = (chunkIndex >> 24) & 0xFF
          ..[1] = (chunkIndex >> 16) & 0xFF
          ..[2] = (chunkIndex >> 8) & 0xFF
          ..[3] = chunkIndex & 0xFF);
        payload.add(chunkData);

        await _sendFileTransferMessage(
          peerId: session.peerId,
          type: FileTransferMessageType.chunk,
          fileId: session.fileId,
          data: payload.toBytes(),
        );

        session.inFlightChunks.add(chunkIndex);
        session.chunkSentTimestamp[chunkIndex] = DateTime.now().millisecondsSinceEpoch;
        session.chunkRetryCount.putIfAbsent(chunkIndex, () => 0);
      } finally {
        await raf.close();
      }
    }
  }

  // ── ACK TIMEOUT ──

  void _startAckTimer(FileTransferSession session) {
    _ackTimers[session.fileId]?.cancel();
    _ackTimers[session.fileId] = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkAckTimeouts(session),
    );
  }

  void _checkAckTimeouts(FileTransferSession session) {
    if (session.state != FileTransferState.transferring) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final chunkIndex in session.inFlightChunks.toList()) {
      final sentAt = session.chunkSentTimestamp[chunkIndex] ?? now;
      if (now - sentAt > session.ackTimeoutMs) {
        final retries = session.chunkRetryCount[chunkIndex] ?? 0;
        if (retries >= FileTransferSession.maxChunkRetries) {
          debugPrint('FileTransfer: Chunk $chunkIndex exceeded max retries, aborting');
          session.state = FileTransferState.failed;
          _ackTimers[session.fileId]?.cancel();
          _transferUpdateController.add(session);
          notifyListeners();
          return;
        }
        // Resend chunk
        session.chunkRetryCount[chunkIndex] = retries + 1;
        session.inFlightChunks.remove(chunkIndex);
        debugPrint('FileTransfer: ACK timeout for chunk $chunkIndex, resending (retry ${retries + 1})');
      }
    }

    // Fill window after removing timed-out chunks
    _sendNextChunks(session);

    // Check for stale transfer (no activity for 10 minutes)
    if (now - session.lastActivityTimestamp > staleThreshold.inMilliseconds) {
      debugPrint('FileTransfer: Transfer ${session.fileId} stale, aborting');
      session.state = FileTransferState.failed;
      _ackTimers[session.fileId]?.cancel();
      _transferUpdateController.add(session);
      notifyListeners();
    }
  }

  // ── INTEGRITY VALIDATION ──

  Future<void> _verifyAndComplete(FileTransferSession session) async {
    session.state = FileTransferState.verifying;
    _transferUpdateController.add(session);

    if (session.filePath == null) {
      session.state = FileTransferState.failed;
      return;
    }

    final file = File(session.filePath!);
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes);

    if (listEquals(Uint8List.fromList(hash.bytes), session.metadata.sha256Hash)) {
      // Move from temp to final location
      final docsDir = await getApplicationDocumentsDirectory();
      final finalPath = '${docsDir.path}/peerchat_files/${session.metadata.fileName}';
      final finalDir = Directory('${docsDir.path}/peerchat_files');
      if (!await finalDir.exists()) await finalDir.create(recursive: true);

      await file.copy(finalPath);
      await file.delete();

      session.filePath = finalPath;
      session.state = FileTransferState.completed;
      await _removeTransferState(session.fileId);
      debugPrint('FileTransfer: Verified and saved: $finalPath');
    } else {
      session.state = FileTransferState.failed;
      debugPrint('FileTransfer: SHA-256 mismatch! Transfer corrupted.');
      await file.delete();
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  // ── CRASH RECOVERY ──

  Future<void> _resumeIncompleteTransfers() async {
    final database = await _db.db;
    final rows = await database.query('file_transfers',
      where: 'state = ?',
      whereArgs: [FileTransferState.transferring.index],
    );

    for (final row in rows) {
      debugPrint('FileTransfer: Found incomplete transfer: ${row['file_id']}');
      // For receiving transfers, send RESUME_FROM to sender
      if (row['direction'] == TransferDirection.receiving.index) {
        final peerId = row['peer_id'] as String;
        final fileId = row['file_id'] as String;
        final receivedChunks = row['received_chunks'] as int? ?? 0;

        final resumeData = Uint8List(4)
          ..[0] = (receivedChunks >> 24) & 0xFF
          ..[1] = (receivedChunks >> 16) & 0xFF
          ..[2] = (receivedChunks >> 8) & 0xFF
          ..[3] = receivedChunks & 0xFF;

        await _sendFileTransferMessage(
          peerId: peerId,
          type: FileTransferMessageType.resumeFrom,
          fileId: fileId,
          data: resumeData,
        );
      }
    }
  }

  Future<void> _persistTransferState(FileTransferSession session) async {
    final database = await _db.db;
    await database.insert(
      'file_transfers',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _removeTransferState(String fileId) async {
    final database = await _db.db;
    await database.delete('file_transfers', where: 'file_id = ?', whereArgs: [fileId]);
  }

  // ── TEMP FILE CLEANUP ──

  Future<void> _cleanupTempFiles() async {
    final tempDir = await getTemporaryDirectory();
    final files = tempDir.listSync().whereType<File>();
    final now = DateTime.now();

    for (final file in files) {
      if (file.path.contains('peerchat_transfer_')) {
        final stat = await file.stat();
        if (now.difference(stat.modified) > tempFileMaxAge) {
          await file.delete();
          debugPrint('FileTransfer: Cleaned up old temp file: ${file.path}');
        }
      }
    }
  }

  // ── DISK PRESSURE CHECK ──

  Future<int> _getAvailableStorage() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final stat = await Process.run('df', ['-k', tempDir.path]);
      // Fallback: assume plenty of storage if we can't check
      if (stat.exitCode != 0) return 1024 * 1024 * 1024; // 1GB
      final lines = stat.stdout.toString().split('\n');
      if (lines.length < 2) return 1024 * 1024 * 1024;
      final parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length < 4) return 1024 * 1024 * 1024;
      return int.tryParse(parts[3]) ?? (1024 * 1024 * 1024);
    } catch (_) {
      return 1024 * 1024 * 1024; // Fallback: assume 1GB
    }
  }

  // ── TRANSPORT HELPER ──

  Future<void> _sendFileTransferMessage({
    required String peerId,
    required FileTransferMessageType type,
    required String fileId,
    required Uint8List data,
  }) async {
    final transportId = _connectionManager.getTransportId(peerId);
    if (transportId == null) {
      debugPrint('FileTransfer: Cannot send — no transport for $peerId');
      return;
    }

    // Protocol: [0xFE] [type:1] [fileId:36] [data...]
    final buffer = BytesBuilder();
    buffer.addByte(0xFE); // File transfer protocol marker
    buffer.addByte(type.index);
    buffer.add(utf8.encode(fileId.padRight(36)));
    buffer.add(data);

    await _transportService.sendMessage(transportId, buffer.toBytes());
  }

  // ── METADATA ENCODING ──

  Uint8List _encodeMetadata(FileMetadata metadata) {
    final json = jsonEncode({
      'fileName': metadata.fileName,
      'fileSize': metadata.fileSize,
      'mimeType': metadata.mimeType,
      'totalChunks': metadata.totalChunks,
      'sha256': base64Encode(metadata.sha256Hash),
    });
    return utf8.encode(json);
  }

  FileMetadata? _decodeMetadata(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return FileMetadata(
        fileId: '', // Will be set by caller
        fileName: json['fileName'] as String,
        fileSize: json['fileSize'] as int,
        mimeType: json['mimeType'] as String,
        sha256Hash: base64Decode(json['sha256'] as String),
        totalChunks: json['totalChunks'] as int,
      );
    } catch (e) {
      debugPrint('FileTransfer: Failed to decode metadata: $e');
      return null;
    }
  }

  /// Check if a raw transport message is a file transfer protocol message.
  static bool isFileTransferMessage(Uint8List data) {
    return data.isNotEmpty && data[0] == 0xFE;
  }

  /// Parse and dispatch a file transfer protocol message.
  Future<void> dispatchRawMessage(String fromPeerId, Uint8List data) async {
    if (data.length < 38) return; // 1 marker + 1 type + 36 fileId

    final type = FileTransferMessageType.values[data[1]];
    final fileId = utf8.decode(data.sublist(2, 38)).trim();
    final payload = data.sublist(38);

    await handleFileTransferMessage(
      fromPeerId: fromPeerId,
      type: type,
      fileId: fileId,
      data: payload,
    );
  }

  @override
  void dispose() {
    for (final timer in _ackTimers.values) {
      timer.cancel();
    }
    _transferUpdateController.close();
    _incomingRequestController.close();
    super.dispose();
  }
}
