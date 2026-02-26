import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/file_transfer.dart';
import '../config/limits_config.dart';
import '../config/timer_config.dart';
import '../config/protocol_config.dart';
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
  Stream<FileTransferSession> get onTransferUpdate =>
      _transferUpdateController.stream;

  /// Stream for incoming transfer requests (UI shows accept/reject dialog).
  final StreamController<FileTransferSession> _incomingRequestController =
      StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onIncomingRequest =>
      _incomingRequestController.stream;

  /// ACK timeout timers per file transfer.
  final Map<String, Timer> _ackTimers = {};

  FileTransferService(
      this._db, this._transportService, this._connectionManager);

  /// Initialize the service: clean up old temp files, resume incomplete transfers.
  Future<void> init() async {
    await _cleanupTempFiles();
    await _resumeIncompleteTransfers();
  }

  /// Get all active transfers.
  List<FileTransferSession> get activeTransfers => _transfers.values.toList();

  /// Get pending incoming requests.
  List<FileTransferSession> get pendingRequests =>
      _pendingIncoming.values.toList();
  List<FileTransferSession> transfersForPeer(String peerId) =>
      _transfers.values.where((t) => t.peerId == peerId).toList();

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
      debugPrint(
          'FileTransfer: Cannot send — peer $peerId not directly connected');
      return null;
    }

    if (!_connectionManager.peerSupportsFileTransfer(
      peerId,
      defaultValue: false,
    )) {
      debugPrint(
          'FileTransfer: Cannot send — peer $peerId reports file transfer disabled');
      return null;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      debugPrint('FileTransfer: File not found: $filePath');
      return null;
    }

    final fileSize = await file.length();
    if (fileSize > FileTransferLimits.maxSendFileSizeBytes) {
      debugPrint(
          'FileTransfer: Cannot send — file too large ($fileSize bytes > ${FileTransferLimits.maxSendFileSizeBytes} bytes)');
      return null;
    }
    final fileName = filePath.split(Platform.pathSeparator).last;
    final prefix = peerId.length >= MessageLimits.generatedIdSenderPrefixLength
        ? peerId.substring(0, MessageLimits.generatedIdSenderPrefixLength)
        : peerId;
    // File transfer protocol reserves 36 chars for fileId on wire.
    final compactUuid = const Uuid()
        .v4()
        .replaceAll('-', '')
        .substring(0, MessageLimits.generatedIdUuidFragmentLength);
    final fileId = '${prefix}_$compactUuid';

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
      ackTimeoutMs: _ackTimeoutForPeer(peerId),
    );

    _transfers[fileId] = session;
    await _persistTransferState(session);

    // Send FILE_META message
    await _sendFileTransferMessage(
      peerId: peerId,
      type: FileTransferMessageType.fileMeta,
      fileId: fileId,
      data: _encodeMetadata(metadata),
    );

    debugPrint(
        'FileTransfer: Initiated send of "$fileName" ($totalChunks chunks) to $peerId');
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
        await _handleFileReject(fileId);
        break;
      case FileTransferMessageType.chunk:
        await _handleChunk(fromPeerId, fileId, data);
        break;
      case FileTransferMessageType.chunkAck:
        await _handleChunkAck(fileId, data);
        break;
      case FileTransferMessageType.fileComplete:
        await _handleFileComplete(fileId);
        break;
      case FileTransferMessageType.resumeFrom:
        await _handleResumeFrom(fileId, data);
        break;
      case FileTransferMessageType.cancelTransfer:
        await _handleCancel(fileId);
        break;
      case FileTransferMessageType.transferPaused:
        await _handleTransferPaused(fileId);
        break;
      case FileTransferMessageType.transferResumed:
        await _handleTransferResumed(fileId);
        break;
    }
  }

  /// Accept a pending incoming transfer.
  Future<void> acceptTransfer(String fileId) async {
    final session = _pendingIncoming.remove(fileId);
    if (session == null) return;
    session.ackTimeoutMs = _ackTimeoutForPeer(session.peerId);

    // Disk pressure check
    final available = await _getAvailableStorage();
    final required = session.metadata.fileSize;
    if (available <
        required * FileTransferLimits.minStorageHeadroomMultiplier) {
      debugPrint(
          'FileTransfer: Insufficient storage. Available: $available, Required: $required');
      session.state = FileTransferState.failed;
      await _sendFileTransferMessage(
        peerId: session.peerId,
        type: FileTransferMessageType.fileReject,
        fileId: fileId,
        data: utf8.encode(FileTransferProtocolConfig.insufficientStorageReason),
      );
      _transferUpdateController.add(session);
      notifyListeners();
      return;
    }

    // Create per-transfer temp directory to store chunks safely by index.
    final tempPath = await _transferTempDirPath(fileId);
    final tempDirEntity = Directory(tempPath);
    if (!await tempDirEntity.exists()) {
      await tempDirEntity.create(recursive: true);
    }
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
    session.cancelledByPeer = false;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.cancelTransfer,
      fileId: fileId,
      data: Uint8List(0),
    );

    await _cleanupReceivingArtifacts(session);

    await _removeTransferState(fileId);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> pauseTransfer(String fileId) async {
    final session = _transfers[fileId];
    if (session == null) return;
    if (session.direction != TransferDirection.sending) return;
    if (session.state != FileTransferState.transferring) return;

    session.state = FileTransferState.paused;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);
    session.inFlightChunks.clear();
    session.chunkSentTimestamp.clear();
    session.chunkRetryCount.clear();

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.transferPaused,
      fileId: fileId,
      data: Uint8List(0),
    );

    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> resumeTransfer(String fileId) async {
    final session = _transfers[fileId];
    if (session == null) return;
    if (session.direction != TransferDirection.sending) return;
    if (session.state != FileTransferState.paused &&
        session.state != FileTransferState.failed) {
      return;
    }

    session.ackTimeoutMs = _ackTimeoutForPeer(session.peerId);
    session.state = FileTransferState.transferring;
    session.inFlightChunks.clear();
    session.chunkSentTimestamp.clear();
    session.chunkRetryCount.clear();

    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.transferResumed,
      fileId: fileId,
      data: Uint8List(0),
    );

    await _sendNextChunks(session);
    _startAckTimer(session);

    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  void onPeerReconnected(String peerId) {
    for (final session in _transfers.values.where((t) => t.peerId == peerId)) {
      if (session.state == FileTransferState.transferring &&
          session.direction == TransferDirection.receiving) {
        _requestResumeFromSender(session);
      }
    }
  }

  // ── INTERNAL HANDLERS ──

  Future<void> _handleFileMeta(
      String fromPeerId, String fileId, Uint8List data) async {
    final metadata = _decodeMetadata(fileId, data);
    if (metadata == null) return;
    if (metadata.fileSize > FileTransferLimits.maxSendFileSizeBytes) {
      debugPrint(
          'FileTransfer: Rejecting incoming file too large (${metadata.fileSize} bytes > ${FileTransferLimits.maxSendFileSizeBytes} bytes)');
      await _sendFileTransferMessage(
        peerId: fromPeerId,
        type: FileTransferMessageType.fileReject,
        fileId: fileId,
        data: utf8.encode(FileTransferProtocolConfig.fileTooLargeReason),
      );
      return;
    }

    final session = FileTransferSession(
      fileId: fileId,
      peerId: fromPeerId,
      metadata: metadata,
      direction: TransferDirection.receiving,
    );

    _pendingIncoming[fileId] = session;
    _incomingRequestController.add(session);
    debugPrint(
        'FileTransfer: Incoming request — "${metadata.fileName}" (${metadata.fileSize} bytes)');
    notifyListeners();
  }

  Future<void> _handleFileAccept(String fileId) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) {
      return;
    }

    session.state = FileTransferState.transferring;
    debugPrint(
        'FileTransfer: Peer accepted transfer $fileId, starting chunk stream');

    // Start sending chunks
    await _sendNextChunks(session);
    _startAckTimer(session);
    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleFileReject(String fileId) async {
    final session = _transfers.remove(fileId);
    if (session == null) return;

    session.state = FileTransferState.failed;
    session.rejectedByPeer = true;
    await _removeTransferState(fileId);
    debugPrint('FileTransfer: Peer rejected transfer $fileId');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleChunk(
      String fromPeerId, String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.receiving) {
      return;
    }

    // Parse chunk: first 4 bytes = index, rest = data
    if (data.length < FileTransferLimits.chunkHeaderBytes) return;
    final chunkIndex =
        (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
    final chunkData = data.sublist(FileTransferLimits.chunkHeaderBytes);

    // Skip if already received (dedup)
    if (session.chunkTracker.isReceived(chunkIndex)) return;

    // Store each chunk as a separate temp part file.
    final tempDir = await _ensureReceiverTempDir(session);
    final chunkFile = File(_chunkTempPath(tempDir, chunkIndex));
    await chunkFile.writeAsBytes(chunkData, flush: false);

    session.chunkTracker.markReceived(chunkIndex);
    session.lastActivityTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Send cumulative ACK
    final highestContiguous = session.chunkTracker.highestContiguous;
    final ackData = Uint8List(FileTransferLimits.chunkHeaderBytes)
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
    if (session.chunkTracker.receivedCount %
            FileTransferLimits.statePersistEveryNChunks ==
        0) {
      await _persistTransferState(session);
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleChunkAck(String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) {
      return;
    }

    if (data.length < FileTransferLimits.chunkHeaderBytes) return;
    final highestContiguous =
        (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];

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
      await _persistTransferState(session);
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleFileComplete(String fileId) async {
    final session = _transfers[fileId];
    if (session == null) return;
    if (session.direction == TransferDirection.receiving &&
        !session.chunkTracker.isComplete) {
      // Ignore premature complete; receiver finalizes on hash verification.
      return;
    }

    session.state = FileTransferState.completed;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);
    await _removeTransferState(fileId);
    debugPrint('FileTransfer: Transfer $fileId marked complete by peer');
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleResumeFrom(String fileId, Uint8List data) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.sending) {
      return;
    }

    if (session.state == FileTransferState.paused) {
      await _sendFileTransferMessage(
        peerId: session.peerId,
        type: FileTransferMessageType.transferPaused,
        fileId: fileId,
        data: Uint8List(0),
      );
      return;
    }

    if (data.length < FileTransferLimits.chunkHeaderBytes) return;
    final resumeIndex =
        (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];

    // Mark all chunks before resumeIndex as received
    for (int i = 0; i < resumeIndex; i++) {
      session.chunkTracker.markReceived(i);
    }

    session.state = FileTransferState.transferring;
    session.inFlightChunks.clear();
    debugPrint('FileTransfer: Resuming $fileId from chunk $resumeIndex');

    await _sendNextChunks(session);
    _startAckTimer(session);
    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleTransferPaused(String fileId) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.receiving) {
      return;
    }
    if (session.state == FileTransferState.completed ||
        session.state == FileTransferState.cancelled) {
      return;
    }

    session.state = FileTransferState.paused;
    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleTransferResumed(String fileId) async {
    final session = _transfers[fileId];
    if (session == null || session.direction != TransferDirection.receiving) {
      return;
    }
    if (session.state == FileTransferState.completed ||
        session.state == FileTransferState.cancelled) {
      return;
    }

    session.state = FileTransferState.transferring;
    await _requestResumeFromSender(session);
    await _persistTransferState(session);
    _transferUpdateController.add(session);
    notifyListeners();
  }

  Future<void> _handleCancel(String fileId) async {
    final session =
        _transfers.remove(fileId) ?? _pendingIncoming.remove(fileId);
    if (session == null) return;

    session.state = FileTransferState.cancelled;
    session.cancelledByPeer = true;
    _ackTimers[fileId]?.cancel();
    _ackTimers.remove(fileId);
    await _cleanupReceivingArtifacts(session);
    await _removeTransferState(fileId);
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
      if (session.state != FileTransferState.transferring) break;
      final chunkIndex = session.nextChunkToSend;
      if (chunkIndex == null) break;

      // Read chunk from file
      final raf = await file.open(mode: FileMode.read);
      try {
        if (session.state != FileTransferState.transferring) break;
        await raf.setPosition(chunkIndex * FileMetadata.chunkSize);
        final remaining =
            session.metadata.fileSize - (chunkIndex * FileMetadata.chunkSize);
        final readSize = remaining < FileMetadata.chunkSize
            ? remaining
            : FileMetadata.chunkSize;
        final chunkData = await raf.read(readSize);
        if (session.state != FileTransferState.transferring) break;

        // Prepend chunk index (4 bytes)
        final payload = BytesBuilder();
        payload.add(Uint8List(FileTransferLimits.chunkHeaderBytes)
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
        if (session.state != FileTransferState.transferring) break;

        session.inFlightChunks.add(chunkIndex);
        session.chunkSentTimestamp[chunkIndex] =
            DateTime.now().millisecondsSinceEpoch;
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
      FileTransferTimerConfig.ackCheckInterval,
      (_) => _checkAckTimeouts(session),
    );
  }

  Future<void> _checkAckTimeouts(FileTransferSession session) async {
    if (session.state != FileTransferState.transferring) return;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final chunkIndex in session.inFlightChunks.toList()) {
      final sentAt = session.chunkSentTimestamp[chunkIndex] ?? now;
      if (now - sentAt > session.ackTimeoutMs) {
        final retries = session.chunkRetryCount[chunkIndex] ?? 0;
        if (retries >= FileTransferSession.maxChunkRetries) {
          debugPrint(
              'FileTransfer: Chunk $chunkIndex exceeded max retries, aborting');
          session.state = FileTransferState.failed;
          _ackTimers[session.fileId]?.cancel();
          await _cleanupReceivingArtifacts(session);
          await _removeTransferState(session.fileId);
          _transferUpdateController.add(session);
          notifyListeners();
          return;
        }
        // Resend chunk
        session.chunkRetryCount[chunkIndex] = retries + 1;
        session.inFlightChunks.remove(chunkIndex);
        debugPrint(
            'FileTransfer: ACK timeout for chunk $chunkIndex, resending (retry ${retries + 1})');
      }
    }

    // Fill window after removing timed-out chunks
    await _sendNextChunks(session);

    // Check for stale transfer (no activity for 10 minutes)
    if (now - session.lastActivityTimestamp >
        FileTransferTimerConfig.staleThreshold.inMilliseconds) {
      debugPrint('FileTransfer: Transfer ${session.fileId} stale, aborting');
      session.state = FileTransferState.failed;
      _ackTimers[session.fileId]?.cancel();
      await _cleanupReceivingArtifacts(session);
      await _removeTransferState(session.fileId);
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
      await _removeTransferState(session.fileId);
      return;
    }

    final chunkDir = Directory(session.filePath!);
    if (!await chunkDir.exists()) {
      session.state = FileTransferState.failed;
      await _removeTransferState(session.fileId);
      _transferUpdateController.add(session);
      notifyListeners();
      return;
    }

    // Re-assemble chunks in order.
    final assembledPath =
        '${chunkDir.path}${Platform.pathSeparator}assembled.tmp';
    final assembledFile = File(assembledPath);
    final output = assembledFile.openWrite(mode: FileMode.writeOnly);

    for (int i = 0; i < session.metadata.totalChunks; i++) {
      final part = File(_chunkTempPath(chunkDir.path, i));
      if (!await part.exists()) {
        await output.close();
        if (await assembledFile.exists()) {
          await assembledFile.delete();
        }
        if (await chunkDir.exists()) {
          await chunkDir.delete(recursive: true);
        }
        session.state = FileTransferState.failed;
        await _removeTransferState(session.fileId);
        _transferUpdateController.add(session);
        notifyListeners();
        return;
      }

      final partBytes = await part.readAsBytes();
      output.add(partBytes);
    }

    await output.close();
    final digest = sha256.convert(await assembledFile.readAsBytes());

    if (listEquals(
        Uint8List.fromList(digest.bytes), session.metadata.sha256Hash)) {
      // Move from temp to final location
      final finalPath =
          await _resolveReceivedFileDestination(session.metadata.fileName);
      await assembledFile.copy(finalPath);
      await chunkDir.delete(recursive: true);

      session.filePath = finalPath;
      session.state = FileTransferState.completed;
      await _removeTransferState(session.fileId);
      debugPrint('FileTransfer: Verified and saved: $finalPath');
    } else {
      session.state = FileTransferState.failed;
      debugPrint('FileTransfer: SHA-256 mismatch! Transfer corrupted.');
      if (await assembledFile.exists()) {
        await assembledFile.delete();
      }
      if (await chunkDir.exists()) {
        await chunkDir.delete(recursive: true);
      }
      await _removeTransferState(session.fileId);
    }

    _transferUpdateController.add(session);
    notifyListeners();
  }

  // ── CRASH RECOVERY ──

  Future<void> _resumeIncompleteTransfers() async {
    final database = await _db.db;
    final rows = await database.query(
      'file_transfers',
      where: 'state IN (?, ?)',
      whereArgs: [
        FileTransferState.transferring.index,
        FileTransferState.paused.index,
      ],
    );

    if (rows.isEmpty) return;

    for (final row in rows) {
      final session = _sessionFromRow(row);
      if (session == null) continue;
      _transfers[session.fileId] = session;

      debugPrint('FileTransfer: Restored transfer ${session.fileId}');

      final hasTransport =
          _connectionManager.getTransportId(session.peerId) != null;
      if (!hasTransport) {
        session.state = FileTransferState.paused;
        await _persistTransferState(session);
        continue;
      }

      if (session.direction == TransferDirection.receiving) {
        if (session.state == FileTransferState.transferring) {
          await _requestResumeFromSender(session);
        }
      } else if (session.state == FileTransferState.transferring) {
        await _sendNextChunks(session);
        _startAckTimer(session);
      }
    }

    notifyListeners();
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
    await database
        .delete('file_transfers', where: 'file_id = ?', whereArgs: [fileId]);
  }

  // ── TEMP FILE CLEANUP ──

  Future<void> _cleanupTempFiles() async {
    final tempDir = await getTemporaryDirectory();
    final entities = tempDir.listSync();
    final now = DateTime.now();

    for (final entity in entities) {
      if (entity.path.contains(FileTransferPathConfig.transferTempPrefix)) {
        final stat = await entity.stat();
        if (now.difference(stat.modified) >
            FileTransferTimerConfig.tempFileMaxAge) {
          await entity.delete(recursive: true);
          debugPrint(
              'FileTransfer: Cleaned up old temp artifact: ${entity.path}');
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
      if (stat.exitCode != 0) {
        return FileTransferLimits.fallbackAvailableStorageBytes;
      }
      final lines = stat.stdout.toString().split('\n');
      if (lines.length < 2) {
        return FileTransferLimits.fallbackAvailableStorageBytes;
      }
      final parts = lines[1].split(RegExp(r'\s+'));
      if (parts.length < 4) {
        return FileTransferLimits.fallbackAvailableStorageBytes;
      }
      return (int.tryParse(parts[3]) ??
              FileTransferLimits.fallbackAvailableStorageBytes) *
          FileTransferLimits.dfBlocksToBytesMultiplier;
    } catch (_) {
      return FileTransferLimits.fallbackAvailableStorageBytes;
    }
  }

  int _ackTimeoutForPeer(String peerId) {
    final transportId = _connectionManager.getTransportId(peerId) ?? '';
    final looksBluetooth =
        transportId.contains(':') || transportId.startsWith('BT_');
    return looksBluetooth
        ? FileTransferLimits.ackTimeoutBluetoothMs
        : FileTransferLimits.ackTimeoutWifiMs;
  }

  Future<void> _requestResumeFromSender(FileTransferSession session) async {
    if (session.direction != TransferDirection.receiving) return;
    await _ensureReceiverTempDir(session);
    final resumeIndex = session.chunkTracker.highestContiguous + 1;
    final resumeData = Uint8List(FileTransferLimits.chunkHeaderBytes)
      ..[0] = (resumeIndex >> 24) & 0xFF
      ..[1] = (resumeIndex >> 16) & 0xFF
      ..[2] = (resumeIndex >> 8) & 0xFF
      ..[3] = resumeIndex & 0xFF;
    await _sendFileTransferMessage(
      peerId: session.peerId,
      type: FileTransferMessageType.resumeFrom,
      fileId: session.fileId,
      data: resumeData,
    );
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
    buffer.addByte(FileTransferLimits.protocolMarker);
    buffer.addByte(type.index);
    buffer.add(utf8.encode(_wireFileId(fileId)));
    buffer.add(data);

    await _transportService.sendMessage(transportId, buffer.toBytes());
  }

  // ── METADATA ENCODING ──

  Uint8List _encodeMetadata(FileMetadata metadata) {
    final json = jsonEncode({
      'fileId': metadata.fileId,
      'fileName': metadata.fileName,
      'fileSize': metadata.fileSize,
      'mimeType': metadata.mimeType,
      'totalChunks': metadata.totalChunks,
      'sha256': base64Encode(metadata.sha256Hash),
    });
    return utf8.encode(json);
  }

  FileMetadata? _decodeMetadata(String fileId, Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return FileMetadata(
        fileId: (json['fileId'] as String?) ?? fileId,
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
    return data.isNotEmpty &&
        data[FileTransferProtocolConfig.markerOffset] ==
            FileTransferLimits.protocolMarker;
  }

  /// Parse and dispatch a file transfer protocol message.
  Future<void> dispatchRawMessage(String fromPeerId, Uint8List data) async {
    const minHeaderLength = FileTransferProtocolConfig.prefixHeaderBytes +
        FileTransferLimits.wireFileIdLength;
    if (data.length < minHeaderLength) return;

    final type = FileTransferMessageType
        .values[data[FileTransferProtocolConfig.typeOffset]];
    final fileId = utf8
        .decode(data.sublist(
            FileTransferProtocolConfig.prefixHeaderBytes,
            FileTransferProtocolConfig.prefixHeaderBytes +
                FileTransferLimits.wireFileIdLength))
        .trim();
    final payload = data.sublist(FileTransferProtocolConfig.prefixHeaderBytes +
        FileTransferLimits.wireFileIdLength);

    await handleFileTransferMessage(
      fromPeerId: fromPeerId,
      type: type,
      fileId: fileId,
      data: payload,
    );
  }

  Future<String> _transferTempDirPath(String fileId) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}${Platform.pathSeparator}${FileTransferPathConfig.transferTempPrefix}$fileId';
  }

  Future<String> _resolveReceivedFileDestination(
      String originalFileName) async {
    final sharedDir = await _resolveSharedPeerChatDirectory();
    if (sharedDir != null) {
      return _buildUniquePath(sharedDir, originalFileName);
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final fallbackDir = Directory(
        '${docsDir.path}${Platform.pathSeparator}${FileTransferPathConfig.fallbackReceivedFolderName}');
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    debugPrint(
        'FileTransfer: Shared storage unavailable, using app storage at ${fallbackDir.path}');
    return _buildUniquePath(fallbackDir, originalFileName);
  }

  Future<Directory?> _resolveSharedPeerChatDirectory() async {
    if (!Platform.isAndroid) return null;

    final hasAccess = await _ensureSharedStorageAccess();
    if (!hasAccess) return null;

    final appExternalDir = await getExternalStorageDirectory();
    if (appExternalDir == null) return null;

    final normalized = appExternalDir.path.replaceAll('\\', '/');
    final androidIndex = normalized.indexOf('/Android/');
    if (androidIndex <= 0) {
      return null;
    }

    final rootPath = normalized.substring(0, androidIndex);
    final peerChatDir = Directory(
        '$rootPath/${FileTransferPathConfig.androidSharedFolderName}');
    if (!await peerChatDir.exists()) {
      await peerChatDir.create(recursive: true);
    }
    return peerChatDir;
  }

  Future<bool> _ensureSharedStorageAccess() async {
    if (!Platform.isAndroid) return false;

    try {
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      final requestedManage = await Permission.manageExternalStorage.request();
      if (requestedManage.isGranted) return true;
    } catch (_) {
      // Continue to legacy permission fallback below.
    }

    try {
      final storageStatus = await Permission.storage.status;
      if (storageStatus.isGranted) return true;

      final requestedStorage = await Permission.storage.request();
      return requestedStorage.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<String> _buildUniquePath(Directory dir, String fileName) async {
    final safeName = _sanitizeFileName(fileName);
    final extensionIndex = safeName.lastIndexOf('.');
    final hasExtension = extensionIndex > 0;
    final base =
        hasExtension ? safeName.substring(0, extensionIndex) : safeName;
    final extension = hasExtension ? safeName.substring(extensionIndex) : '';

    var candidate = '${dir.path}${Platform.pathSeparator}$safeName';
    var counter = 1;
    while (await File(candidate).exists()) {
      candidate =
          '${dir.path}${Platform.pathSeparator}${base}_$counter$extension';
      counter++;
    }
    return candidate;
  }

  String _sanitizeFileName(String input) {
    final sanitized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (sanitized.isEmpty) {
      return '${FileTransferPathConfig.defaultReceivedPrefix}${DateTime.now().millisecondsSinceEpoch}.bin';
    }
    return sanitized;
  }

  String _wireFileId(String fileId) {
    if (fileId.length >= FileTransferLimits.wireFileIdLength) {
      return fileId.substring(0, FileTransferLimits.wireFileIdLength);
    }
    return fileId.padRight(FileTransferLimits.wireFileIdLength);
  }

  String _chunkTempPath(String transferDirPath, int chunkIndex) {
    return '$transferDirPath${Platform.pathSeparator}${FileTransferPathConfig.chunkPartPrefix}$chunkIndex${FileTransferPathConfig.chunkPartExtension}';
  }

  Future<String> _ensureReceiverTempDir(FileTransferSession session) async {
    session.filePath ??= await _transferTempDirPath(session.fileId);
    final dir = Directory(session.filePath!);
    if (await dir.exists()) {
      return dir.path;
    }

    // Clean legacy single-file temp path if present.
    final legacyFile = File(session.filePath!);
    if (await legacyFile.exists()) {
      await legacyFile.delete();
    }

    await dir.create(recursive: true);
    return dir.path;
  }

  Future<void> _cleanupReceivingArtifacts(FileTransferSession session) async {
    if (session.direction != TransferDirection.receiving ||
        session.filePath == null) {
      return;
    }

    final path = session.filePath!;
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  FileTransferSession? _sessionFromRow(Map<String, Object?> row) {
    try {
      final fileId = row['file_id'] as String;
      final peerId = row['peer_id'] as String;
      final directionIndex = (row['direction'] as int?) ?? 0;
      final stateIndex =
          (row['state'] as int?) ?? FileTransferState.pending.index;

      if (directionIndex < 0 ||
          directionIndex >= TransferDirection.values.length ||
          stateIndex < 0 ||
          stateIndex >= FileTransferState.values.length) {
        return null;
      }

      final metadata = FileMetadata(
        fileId: fileId,
        fileName: row['file_name'] as String,
        fileSize: row['file_size'] as int,
        mimeType: row['mime_type'] as String,
        sha256Hash: row['sha256_hash'] as Uint8List,
        totalChunks: row['total_chunks'] as int,
      );

      final session = FileTransferSession(
        fileId: fileId,
        peerId: peerId,
        metadata: metadata,
        direction: TransferDirection.values[directionIndex],
        state: FileTransferState.values[stateIndex],
        filePath: row['file_path'] as String?,
        ackTimeoutMs:
            (row['ack_timeout_ms'] as int?) ?? _ackTimeoutForPeer(peerId),
        lastActivityTimestamp: row['last_activity'] as int?,
        startTimestamp: row['start_timestamp'] as int?,
      );

      final contiguousReceived = (row['received_chunks'] as int?) ?? 0;
      final safeCount = contiguousReceived.clamp(0, metadata.totalChunks);
      for (int i = 0; i < safeCount; i++) {
        session.chunkTracker.markReceived(i);
      }

      return session;
    } catch (e) {
      debugPrint('FileTransfer: Failed to restore transfer row: $e');
      return null;
    }
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
