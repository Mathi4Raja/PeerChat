import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'package:external_path/external_path.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

import '../models/file_transfer.dart';
import '../models/mesh_message.dart';
import 'db_service.dart';
import 'mesh_router_service.dart';
import 'transport_service.dart';

class FileTransferService {
  final DBService _db;
  final MeshRouterService _router;
  final _uuid = const Uuid();

  // Active sessions in memory
  final Map<String, FileTransferSession> _activeSessions = {};
  StreamSubscription? _rawMessageSub;
  
  final _progressController = StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onProgress => _progressController.stream;

  final _requestController = StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onIncomingRequest => _requestController.stream;

  final _completedController = StreamController<FileTransferSession>.broadcast();
  Stream<FileTransferSession> get onTransferCompleted => _completedController.stream;

  Map<String, FileTransferSession> get activeSessions => Map.unmodifiable(_activeSessions);

  FileTransferService(this._db, this._router) {
    _listenToMeshPackets();
    _listenToNativeTransport();
  }

  void _listenToMeshPackets() {
    _rawMessageSub = _router.onRawMessageReceived.listen((message) {
      if (message.type == MessageType.fileTransfer) {
        unawaited(_handleFilePacket(message));
      }
    });
  }

  void _listenToNativeTransport() {
    _router.transportService.onFileProgress.listen((event) {
      _handleNativeFileProgress(event);
    });
  }

  void _handleNativeFileProgress(FileTransferProgressEvent event) {
    final session = _activeSessions[event.fileId];
    if (session == null) return;

    session.progress = event.progress;
    
    if (event.isCompleted) {
      session.status = FileTransferStatus.completed;
      _addEvent('Native transfer completed: ${event.fileId}');
      
      if (session.isIncoming && event.localPath != null) {
        unawaited(_finalizeNativeFile(session, event.localPath!));
      } else if (!session.isIncoming) {
        unawaited(_db.updateFileTransferStatus(session.fileId, FileTransferStatus.completed.index));
        _completedController.add(session);
      }
    } else {
      session.status = FileTransferStatus.transferring;
    }

    _progressController.add(session);
  }

  Future<void> _finalizeNativeFile(FileTransferSession session, String tempPath) async {
    try {
      final dbRow = await _db.getFileTransfer(session.fileId);
      if (dbRow == null || dbRow['file_path'] == null) return;

      final targetPath = dbRow['file_path'];
      final targetFile = File(targetPath);
      
      // Ensure directory exists
      await targetFile.parent.create(recursive: true);

      // Move the file from Google's temp location to our DirectShare folder
      try {
        await File(tempPath).rename(targetPath);
      } catch (e) {
        AppLogger.print('Rename failed (possibly cross-partition), falling back to copy/delete: $e');
        await File(tempPath).copy(targetPath);
        await File(tempPath).delete();
      }
      
      await _db.updateFileTransferStatus(session.fileId, FileTransferStatus.completed.index);
      _completedController.add(session);
      _addEvent('Moved native file to target: $targetPath');
    } catch (e) {
      AppLogger.e('Failed to finalize native file for ${session.fileId}', e);
      session.status = FileTransferStatus.failed;
      _progressController.add(session);
    }
  }

  Future<void> _handleFilePacket(MeshMessage message) async {
    final senderId = message.senderPeerId;
    try {
      if (message.encryptedContent == null) {
        _addEvent(
            'Dropping transfer packet from $senderId: encrypted payload missing');
        return;
      }

      final decrypted = await _router.messageManager.decryptBytes(message);
      if (decrypted == null) {
        _addEvent(
            'Dropping transfer packet from $senderId: decryption failed');
        return;
      }

      final payload = FileTransferPayload.fromBytes(decrypted);
      if (payload.typeIndicator != FileTransferPayload.typeChunk &&
          payload.typeIndicator != FileTransferPayload.typeAck) {
        _addEvent(
          'Packet in: type=${payload.typeIndicator} fileId=${payload.fileId} from=$senderId bytes=${payload.data.length}',
        );
      }

      switch (payload.typeIndicator) {
        case FileTransferPayload.typeMeta:
          await _handleIncomingMeta(senderId, payload);
          break;
        case FileTransferPayload.typeControl:
          await _handleControl(senderId, payload);
          break;
        default:
          _addEvent(
              'Dropping transfer packet for ${payload.fileId}: legacy type ${payload.typeIndicator}');
      }
    } catch (e, stack) {
      AppLogger.e('Failed to process file transfer packet', e, stack);
    }
  }

  Future<SendResult> _sendTransferPayload({
    required String peerId,
    required String fileId,
    required String kind,
    required FileTransferPayload payload,
    required MessagePriority priority,
  }) async {
    final result = await _router.sendDataMessage(
      recipientPeerId: peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: priority,
    );
    final noisyDataPacket =
        (kind.startsWith('CHUNK#') || kind.startsWith('ACK#')) &&
            result == SendResult.routed;
    if (!noisyDataPacket) {
      _addEvent('Packet out: type=$kind fileId=$fileId to=$peerId result=$result');
    }
    if (result == SendResult.failed) {
      AppLogger.w(
          '[FileTransfer] sendDataMessage failed for type=$kind fileId=$fileId to=$peerId');
    }
    return result;
  }


  // --- Bitmask Helpers ---

  Uint8List createBitmask(int totalChunks) {
    final byteLen = (totalChunks / 8).ceil();
    return Uint8List(byteLen);
  }

  bool isChunkReceived(Uint8List bitmask, int index) {
    final byteIdx = index ~/ 8;
    final bitIdx = index % 8;
    if (byteIdx >= bitmask.length) return false;
    return (bitmask[byteIdx] & (1 << bitIdx)) != 0;
  }

  void setChunkReceived(Uint8List bitmask, int index) {
    final byteIdx = index ~/ 8;
    final bitIdx = index % 8;
    if (byteIdx >= bitmask.length) return;
    bitmask[byteIdx] |= (1 << bitIdx);
  }

  // --- Sender Logic ---

  Future<void> startTransfer(String peerId, String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception("File not found");

    final fileName = p.basename(filePath);
    final fileSize = await file.length();


    final fileId = _uuid.v4();
    
    // Hash file for verification
    final hash = (await sha256.bind(file.openRead()).last).toString();
    
    final meta = FileMetadata(
      fileId: fileId,
      name: fileName,
      size: fileSize,
      type: 'application/octet-stream', // Default for now
      hash: hash,
      totalChunks: 1, // Native transfer counts as 1 item
    );

    final session = FileTransferSession(
      fileId: fileId,
      peerId: peerId,
      metadata: meta,
      status: FileTransferStatus.requesting,
      isIncoming: false,
    );
    
    _activeSessions[fileId] = session;
    _addEvent(
        'Start transfer: fileId=$fileId peer=$peerId name=$fileName size=$fileSize');

    // Persist to DB
    await _db.insertFileTransfer({
      'id': fileId,
      'peer_id': peerId,
      'file_name': fileName,
      'file_size': fileSize,
      'file_path': filePath,
      'status': FileTransferStatus.requesting.index,
      'total_chunks': 1,
      'file_hash': hash,
      'is_incoming': 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Send META packet
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeMeta,
      data: utf8.encode(jsonEncode(meta.toMap())),
    );

    final result = await _sendTransferPayload(
      peerId: peerId,
      fileId: fileId,
      kind: 'META',
      payload: payload,
      priority: MessagePriority.high,
    );
    if (result == SendResult.failed) {
      session.status = FileTransferStatus.failed;
      await _db.updateFileTransferStatus(fileId, FileTransferStatus.failed.index);
      _progressController.add(session);
      _addEvent('Transfer start failed: unable to send META for $fileId');
    }
  }

  // --- Receiver Logic ---

  Future<void> _handleIncomingMeta(String senderId, FileTransferPayload payload) async {
    final meta = FileMetadata.fromMap(jsonDecode(utf8.decode(payload.data)));
    _addEvent(
        'META in: fileId=${meta.fileId} from=$senderId name=${meta.name} size=${meta.size}');
    
    // Security: Sanitize filename and validate metadata
    final sanitizedName = _sanitizeFileName(meta.name);
    // Native transfer doesn't use chunks, so we just validate basic bounds
    if (meta.size <= 0) {
      _addEvent('Rejecting META for ${meta.fileId}: invalid size (${meta.size})');
      return;
    }

    var sessionRow = await _db.getFileTransfer(meta.fileId);

    if (sessionRow == null) {
      final uniquePath = await _getUniqueFilePath(await getTargetDir(false), sanitizedName);

      final session = FileTransferSession(
        fileId: meta.fileId,
        peerId: senderId,
        metadata: meta,
        status: FileTransferStatus.requesting,
        isIncoming: true,
      );
      
      _activeSessions[meta.fileId] = session;
      _requestController.add(session);
      _addEvent('Incoming transfer request created for ${meta.fileId}');
      
      await _db.insertFileTransfer({
        'id': meta.fileId,
        'peer_id': senderId,
        'file_name': meta.name,
        'file_size': meta.size,
        'file_path': uniquePath,
        'status': FileTransferStatus.requesting.index,
        'total_chunks': 1,
        'file_hash': meta.hash,
        'is_incoming': 1,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      final session = FileTransferSession(
        fileId: meta.fileId,
        peerId: senderId,
        metadata: meta,
        status: FileTransferStatus.values[sessionRow['status']],
        isIncoming: true,
      );
      _activeSessions[meta.fileId] = session;
      _addEvent(
          'Incoming transfer resumed from DB for ${meta.fileId} status=${session.status}');
    }
  }

  // --- Control & Sync ---

  Future<void> _handleControl(String senderId, FileTransferPayload payload) async {
    final session = _activeSessions[payload.fileId];
    if (session == null) {
      _addEvent(
          'Ignoring CONTROL for unknown session ${payload.fileId} from $senderId');
      return;
    }
    if (payload.data.isEmpty) {
      _addEvent('Ignoring CONTROL for ${payload.fileId}: empty payload');
      return;
    }
    final controlIndex = payload.data[0];
    if (controlIndex < 0 || controlIndex >= FileTransferControl.values.length) {
      _addEvent(
          'Ignoring CONTROL for ${payload.fileId}: invalid control index $controlIndex');
      return;
    }

    final controlType = FileTransferControl.values[controlIndex];
    _addEvent('CONTROL in: fileId=${payload.fileId} from=$senderId type=$controlType');
    switch (controlType) {
      case FileTransferControl.accept:
        session.status = FileTransferStatus.accepted;
        await _db.updateFileTransferStatus(
            session.fileId, FileTransferStatus.accepted.index);
        _enqueueTransfer(session.fileId);
        break;
      case FileTransferControl.reject:
        session.status = FileTransferStatus.rejected;
        await _db.updateFileTransferStatus(
            session.fileId, FileTransferStatus.rejected.index);
        _activeSessions.remove(session.fileId);
        _addEvent('Transfer rejected by peer for ${session.fileId}');
        break;
      case FileTransferControl.abort:
        session.status = FileTransferStatus.aborted;
        await _db.updateFileTransferStatus(
            session.fileId, FileTransferStatus.aborted.index);
        session.close();
        _activeSessions.remove(session.fileId);
        _addEvent('Transfer aborted by peer for ${session.fileId}');
        break;
      case FileTransferControl.pause:
        session.status = FileTransferStatus.paused;
        await _db.updateFileTransferStatus(
            session.fileId, FileTransferStatus.paused.index);
        _addEvent('Transfer paused by peer for ${session.fileId}');
        break;
      case FileTransferControl.resume:
        break;
    }
    _progressController.add(session);
  }

  // --- Public Control methods ---

  Future<void> acceptTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) {
      _addEvent('acceptTransfer ignored: unknown session $fileId');
      return;
    }
    
    session.status = FileTransferStatus.accepted;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.accepted.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.accept.index,
    );

    await _sendTransferPayload(
      peerId: session.peerId,
      fileId: fileId,
      kind: 'CONTROL_ACCEPT',
      payload: payload,
      priority: MessagePriority.high,
    );
    _addEvent('Transfer accepted locally for $fileId');

    _enqueueTransfer(fileId);
  }

  Future<void> rejectTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) {
      _addEvent('rejectTransfer ignored: unknown session $fileId');
      return;
    }
    
    session.status = FileTransferStatus.rejected;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.rejected.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.reject.index,
    );

    await _sendTransferPayload(
      peerId: session.peerId,
      fileId: fileId,
      kind: 'CONTROL_REJECT',
      payload: payload,
      priority: MessagePriority.high,
    );
    _addEvent('Transfer rejected locally for $fileId');
  }

  Future<String> _getUniqueFilePath(String dir, String name) async {
    final fileName = p.basenameWithoutExtension(name);
    final extension = p.extension(name);
    var targetPath = p.join(dir, name);
    var counter = 1;

    while (await File(targetPath).exists()) {
      targetPath = p.join(dir, "$fileName ($counter)$extension");
      counter++;
    }
    return targetPath;
  }


  String _sanitizeFileName(String name) {
    // Prevent path traversal and remove risky characters
    var sanitized = p.basename(name);
    sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return sanitized;
  }


  void _addEvent(String msg) {
    AppLogger.print("[FileTransfer] $msg");
  }

  Future<String> getTargetDir(bool isWebShare) async {
    final subDir = isWebShare ? 'WebShare' : 'DirectShare';

    if (Platform.isAndroid) {
      // Request Manage External Storage permission
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        final requested = await Permission.manageExternalStorage.request();
        if (!requested.isGranted) {
          _addEvent(
              'Manage external storage permission not granted; falling back to private storage');
          final docs = await getApplicationDocumentsDirectory();
          final dir = Directory(p.join(docs.path, 'PeerChat', subDir));
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir.path;
        }
      }

      final dirs = await ExternalPath.getExternalStorageDirectories();
      final root = (dirs != null && dirs.isNotEmpty) ? dirs.first : '/storage/emulated/0';
      final dir = Directory(p.join(root, 'PeerChat', subDir));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } else {
      // Fallback for iOS or other platforms
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'PeerChat', subDir));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }
  }

  Future<void> openFile(String fileId) async {
    final dbRow = await _db.getFileTransfer(fileId);
    if (dbRow == null || dbRow['file_path'] == null) {
      _addEvent('openFile failed: unknown transfer/file path for $fileId');
      return;
    }
    final path = dbRow['file_path'];
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      AppLogger.print("Error opening file: ${result.message}");
      _addEvent('openFile failed for $fileId: ${result.message}');
    }
  }

  // --- External Controls ---

  void abortTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) {
      _addEvent('abortTransfer ignored: unknown session $fileId');
      return;
    }

    session.status = FileTransferStatus.aborted;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.aborted.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.abort.index,
    );
    
    await _sendTransferPayload(
      peerId: session.peerId,
      fileId: fileId,
      kind: 'CONTROL_ABORT',
      payload: payload,
      priority: MessagePriority.high,
    );
    _addEvent('Transfer aborted locally for $fileId');

    session.close();
    _activeSessions.remove(fileId);
    _progressController.add(session);
  }

  Future<void> resumeTransfer(String fileId) async {
    final dbRow = await _db.getFileTransfer(fileId);
    if (dbRow == null) {
      _addEvent('resumeTransfer failed: unknown transfer $fileId');
      return;
    }

    final meta = FileMetadata(
      fileId: fileId,
      name: dbRow['file_name'],
      size: dbRow['file_size'],
      type: 'application/octet-stream',
      totalChunks: dbRow['total_chunks'],
      hash: dbRow['file_hash'] ?? '',
    );

    final session = FileTransferSession(
      fileId: fileId,
      peerId: dbRow['peer_id'],
      metadata: meta,
      status: FileTransferStatus.transferring,
      isIncoming: dbRow['is_incoming'] == 1,
    );

    _activeSessions[fileId] = session;
    
    // Send resume request
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeResumeSync,
      data: Uint8List(0),
    );

    await _sendTransferPayload(
      peerId: session.peerId,
      fileId: fileId,
      kind: 'RESUME_SYNC',
      payload: payload,
      priority: MessagePriority.high,
    );
    _addEvent('Resume requested for $fileId');
  }

  // --- Queue Management ---
  final List<String> _transferQueue = [];
  static const int maxConcurrentTransfers = 1;

  void _enqueueTransfer(String fileId) {
    if (!_transferQueue.contains(fileId)) {
      _transferQueue.add(fileId);
      _addEvent('Queue enqueue: $fileId (len=${_transferQueue.length})');
    }
    _processQueue();
  }

  void _processQueue() {
    int activeCount = _activeSessions.values.where((s) => 
      s.status == FileTransferStatus.transferring || 
      s.status == FileTransferStatus.accepted).length;

    while (activeCount < maxConcurrentTransfers && _transferQueue.isNotEmpty) {
      final fileId = _transferQueue.removeAt(0);
      final session = _activeSessions[fileId];
      if (session != null && session.status == FileTransferStatus.accepted) {
        _startNativeTransfer(session);
        activeCount++;
      }
    }
  }

  Future<void> _startNativeTransfer(FileTransferSession session) async {
    final dbRow = await _db.getFileTransfer(session.fileId);
    if (dbRow == null || dbRow['file_path'] == null) {
      _addEvent('Cannot start native transfer: DB row missing');
      return;
    }

    session.status = FileTransferStatus.transferring;
    _progressController.add(session);
    _addEvent('Starting native transfer handover: ${session.fileId}');

    final success = await _router.transportService.sendFile(
      session.peerId,
      dbRow['file_path'],
      session.fileId,
    );

    if (!success) {
      session.status = FileTransferStatus.failed;
      await _db.updateFileTransferStatus(session.fileId, FileTransferStatus.failed.index);
      _progressController.add(session);
    }
  }


  Future<void> deleteTransfer(String fileId) async {
    final session = _activeSessions.remove(fileId);
    session?.close();
    await _db.deleteFileTransfer(fileId);
    _addEvent('Transfer deleted: $fileId');
  }

  void dispose() {
    _rawMessageSub?.cancel();
    _progressController.close();
    _requestController.close();
    _completedController.close();
    for (var session in _activeSessions.values) {
      session.close();
    }
  }
}

class FileTransferSession {
  final String fileId;
  final String peerId;
  final FileMetadata metadata;
  FileTransferStatus status;
  double progress;
  final bool isIncoming;

  FileTransferSession({
    required this.fileId,
    required this.peerId,
    required this.metadata,
    this.status = FileTransferStatus.requesting,
    this.progress = 0.0,
    required this.isIncoming,
  }) {
    speedTimer.start();
  }

  final Stopwatch speedTimer = Stopwatch();
  int bytesSinceLastTick = 0;
  double speedMBps = 0.0;
  Duration remainingTime = Duration.zero;
  int _lastTickMs = 0;

  void updateSpeed(int bytes) {
    bytesSinceLastTick += bytes;
    final now = speedTimer.elapsedMilliseconds;
    final delta = now - _lastTickMs;

    if (delta >= 1000) {
      speedMBps = (bytesSinceLastTick / 1024 / 1024) / (delta / 1000);
      
      // Calculate ETA
      if (speedMBps > 0) {
        final remainingBytes = metadata.size * (1.0 - progress);
        final remainingSeconds = (remainingBytes / 1024 / 1024) / speedMBps;
        remainingTime = Duration(seconds: remainingSeconds.toInt());
      } else {
        remainingTime = Duration.zero;
      }

      bytesSinceLastTick = 0;
      _lastTickMs = now;
    }
  }

  void close() {
    // Session cleanup if needed
  }
}