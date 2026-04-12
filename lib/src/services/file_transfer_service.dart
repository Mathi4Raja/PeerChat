import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
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

class FileTransferService {
  final DBService _db;
  final MeshRouterService _router;
  final _uuid = const Uuid();

  static const int chunkSize = 64 * 1024; // 64 KB (Mesh friendly limit)
  static const int slidingWindowSize = 5; // Send 5 chunks in flight

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
  }

  void _listenToMeshPackets() {
    _rawMessageSub = _router.onRawMessageReceived.listen((message) {
      if (message.type == MessageType.fileTransfer) {
        _handleFilePacket(message);
      }
    });
  }

  void _handleFilePacket(MeshMessage message) async {
    final senderId = message.senderPeerId;
    if (message.encryptedContent == null) return;

    final decrypted = await _router.messageManager.decryptBytes(message);
    if (decrypted == null) return;

    final payload = FileTransferPayload.fromBytes(decrypted);
    
    switch (payload.typeIndicator) {
      case FileTransferPayload.typeMeta:
        await _handleIncomingMeta(senderId, payload);
        break;
      case FileTransferPayload.typeControl:
        _handleControl(senderId, payload);
        break;
      case FileTransferPayload.typeChunk:
        await _handleChunk(payload);
        break;
      case FileTransferPayload.typeAck:
        _handleAck(payload);
        break;
      case FileTransferPayload.typeComplete:
        _handleComplete(payload);
        break;
      case FileTransferPayload.typeResumeSync:
        _handleResumeSync(payload);
        break;
    }
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
    
    final totalChunks = (fileSize / chunkSize).ceil();
    final meta = FileMetadata(
      fileId: fileId,
      name: fileName,
      size: fileSize,
      type: 'application/octet-stream', // Default for now
      hash: hash,
      totalChunks: totalChunks,
    );

    final session = FileTransferSession(
      fileId: fileId,
      peerId: peerId,
      metadata: meta,
      status: FileTransferStatus.requesting,
      isIncoming: false,
    );
    
    _activeSessions[fileId] = session;

    // Persist to DB
    await _db.insertFileTransfer({
      'id': fileId,
      'peer_id': peerId,
      'file_name': fileName,
      'file_size': fileSize,
      'file_path': filePath,
      'status': FileTransferStatus.requesting.index,
      'total_chunks': totalChunks,
      'file_hash': hash,
      'received_chunks': createBitmask(totalChunks), // Sender bitmask starts empty (unused for sender)
      'is_incoming': 0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Send META packet
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeMeta,
      data: utf8.encode(jsonEncode(meta.toMap())),
    );

    _router.sendDataMessage(
      recipientPeerId: peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );
  }

  // --- Receiver Logic ---

  Future<void> _handleIncomingMeta(String senderId, FileTransferPayload payload) async {
    final meta = FileMetadata.fromMap(jsonDecode(utf8.decode(payload.data)));
    
    // Security: Sanitize filename and validate metadata
    final sanitizedName = _sanitizeFileName(meta.name);
    if (meta.totalChunks <= 0 || meta.size <= 0 || meta.totalChunks > 1000000) return;
    if (meta.totalChunks != (meta.size / chunkSize).ceil()) return;

    var sessionRow = await _db.getFileTransfer(meta.fileId);
    
    if (sessionRow == null) {
      final uniquePath = await _getUniqueFilePath(await getTargetDir(false), sanitizedName);
      
      final session = FileTransferSession(
        fileId: meta.fileId,
        peerId: senderId,
        metadata: meta,
        status: FileTransferStatus.requesting,
        isIncoming: true,
        receivedBitmask: createBitmask(meta.totalChunks),
      );
      
      _activeSessions[meta.fileId] = session;
      _requestController.add(session);
      
      await _db.insertFileTransfer({
        'id': meta.fileId,
        'peer_id': senderId,
        'file_name': meta.name,
        'file_size': meta.size,
        'file_path': uniquePath,
        'status': FileTransferStatus.requesting.index,
        'total_chunks': meta.totalChunks,
        'file_hash': meta.hash,
        'received_chunks': session.receivedBitmask,
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
        receivedBitmask: sessionRow['received_chunks'],
      );
      _activeSessions[meta.fileId] = session;
      
      if (session.status == FileTransferStatus.accepted || 
          session.status == FileTransferStatus.transferring) {
        _sendResumeSync(session);
      }
    }
  }

  void _sendResumeSync(FileTransferSession session) {
    if (session.receivedBitmask == null) return;
    final payload = FileTransferPayload(
      fileId: session.fileId,
      typeIndicator: FileTransferPayload.typeResumeSync,
      data: session.receivedBitmask!,
    );
    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high, // RESUME_SYNC is high priority
    );
  }

  // --- Control & Sync ---

  void _handleControl(String senderId, FileTransferPayload payload) {
    final session = _activeSessions[payload.fileId];
    if (session == null) return;
    
    final controlType = FileTransferControl.values[payload.data[0]];
    switch (controlType) {
      case FileTransferControl.accept:
        session.status = FileTransferStatus.accepted;
        _sendNextChunks(session);
        break;
      case FileTransferControl.reject:
        session.status = FileTransferStatus.rejected;
        _db.updateFileTransferStatus(session.fileId, FileTransferStatus.rejected.index);
        _activeSessions.remove(session.fileId);
        break;
      case FileTransferControl.abort:
        session.status = FileTransferStatus.aborted;
        _db.updateFileTransferStatus(session.fileId, FileTransferStatus.aborted.index);
        session.close();
        _activeSessions.remove(session.fileId);
        break;
      case FileTransferControl.resume:
        // Peer requested resume sync
        _sendResumeSync(session);
        break;
      default:
        break;
    }
    _progressController.add(session);
  }

  void _handleResumeSync(FileTransferPayload payload) {
    final session = _activeSessions[payload.fileId];
    if (session == null) return;
    
    final remoteBitmask = payload.data;
    
    // Find the first missing chunk to resume from
    int firstMissing = 0;
    for (int i = 0; i < session.metadata.totalChunks; i++) {
       if (!isChunkReceived(remoteBitmask, i)) {
         firstMissing = i;
         break;
       }
    }
    
    session.unackedBase = firstMissing;
    session.nextSeqNum = firstMissing;
    session.status = FileTransferStatus.accepted; // Ready to start
    
    _enqueueTransfer(session.fileId);
  }

  Future<void> _sendChunk(FileTransferSession session, int index) async {
    final dbRow = await _db.getFileTransfer(session.fileId);
    if (dbRow == null) return;
    
    final file = File(dbRow['file_path']);
    if (!await file.exists()) return;

    session.fileHandle ??= await file.open(mode: FileMode.read);
    
    await session.fileHandle!.setPosition(index * chunkSize);
    final data = await session.fileHandle!.read(chunkSize);

    session.updateSpeed(data.length);

    final chunk = FileChunk(index: index, data: data);
    final payload = FileTransferPayload(
      fileId: session.fileId,
      typeIndicator: FileTransferPayload.typeChunk,
      data: chunk.toBytes(),
    );

    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.low,
    );
  }

  void _sendNextChunks(FileTransferSession session) {
    while (session.nextSeqNum < session.unackedBase + slidingWindowSize && 
           session.nextSeqNum < session.metadata.totalChunks) {
      final idx = session.nextSeqNum++;
      session.inFlight.add(idx);
      _sendChunk(session, idx);
    }
  }

  void _handleAck(FileTransferPayload payload) {
    final session = _activeSessions[payload.fileId];
    if (session == null) return;

    final ackedIndex = ByteData.sublistView(payload.data).getUint32(0);
    session.inFlight.remove(ackedIndex);
    
    if (ackedIndex >= session.unackedBase) {
      session.unackedBase = ackedIndex + 1;
      _db.updateFileTransferLastAcked(session.fileId, session.unackedBase);
    }

    // Progress update based on ACKs
    session.progress = session.unackedBase / session.metadata.totalChunks;
    _progressController.add(session);

    if (session.unackedBase == session.metadata.totalChunks) {
      // All chunks acknowledged by receiver
      _sendComplete(session);
    } else {
      _sendNextChunks(session);
    }
  }

  void _sendComplete(FileTransferSession session) async {
    final payload = FileTransferPayload(
      fileId: session.fileId,
      typeIndicator: FileTransferPayload.typeComplete,
      data: Uint8List(0),
    );
    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );
    
    // Sender side cleanup: also mark as completed locally
    session.status = FileTransferStatus.completed;
    await _db.updateFileTransferStatus(session.fileId, FileTransferStatus.completed.index);
    session.close();
    _activeSessions.remove(session.fileId);
    _progressController.add(session);
    _completedController.add(session);
  }

  void _handleComplete(FileTransferPayload payload) {
    final session = _activeSessions[payload.fileId];
    if (session == null) return;
    
    if (session.status == FileTransferStatus.completed) {
      _completedController.add(session);
      _activeSessions.remove(session.fileId);
    }
  }

  // --- Public Control methods ---

  Future<void> acceptTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) return;
    
    session.status = FileTransferStatus.accepted;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.accepted.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.accept.index,
    );

    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );

    _enqueueTransfer(fileId);
  }

  Future<void> rejectTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) return;
    
    session.status = FileTransferStatus.rejected;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.rejected.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.reject.index,
    );

    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );
  }

  Future<void> _handleChunk(FileTransferPayload payload) async {
    final session = _activeSessions[payload.fileId];
    if (session == null) return;
    
    final chunk = FileChunk.fromBytes(payload.data);
    
    if (session.receivedBitmask != null && isChunkReceived(session.receivedBitmask!, chunk.index)) return;

    try {
      if (session.fileHandle == null) {
        final dbRow = await _db.getFileTransfer(session.fileId);
        if (dbRow != null) {
          final file = File(dbRow['file_path']);
          // Use FileMode.write for random-access. Ensure file exists first.
          if (!await file.exists()) {
             await file.create(recursive: true);
          }
          session.fileHandle = await file.open(mode: FileMode.write);
        } else {
          return;
        }
      }
      
      final offset = chunk.index * chunkSize; 
      await session.fileHandle!.setPosition(offset);
      await session.fileHandle!.writeFrom(chunk.data);
      
      session.updateSpeed(chunk.data.length);

      if (session.receivedBitmask != null) {
        setChunkReceived(session.receivedBitmask!, chunk.index);
        
        int count = 0;
        for (int i = 0; i < session.metadata.totalChunks; i++) {
          if (isChunkReceived(session.receivedBitmask!, i)) count++;
        }
        session.progress = count / session.metadata.totalChunks;
        session.status = FileTransferStatus.transferring;
        
        _progressController.add(session);

        if (chunk.index % 50 == 0) {
          await _db.updateFileTransferProgress(session.fileId, session.receivedBitmask!);
        }

        // Always ACK to keep sender window moving
        _sendAck(session, chunk.index);

        if (count == session.metadata.totalChunks) {
          await _verifyAndFinalize(session);
        }
      }
    } catch (e) {
      print("Error writing chunk: $e");
      session.status = FileTransferStatus.failed;
      _progressController.add(session);
    }
  }

  void _sendAck(FileTransferSession session, int index) {
    if (session.status != FileTransferStatus.transferring && session.status != FileTransferStatus.accepted) return;

    final payload = FileTransferPayload(
      fileId: session.fileId,
      typeIndicator: FileTransferPayload.typeAck,
      data: FileChunk.uint32ToBytes(index),
    );
    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.normal, // ACK is normal, not low, to keep window moving
    );
  }

  Future<void> _verifyAndFinalize(FileTransferSession session) async {
    session.status = FileTransferStatus.completed;
    await session.fileHandle?.close();
    session.fileHandle = null;

    final file = File((await _db.getFileTransfer(session.fileId))!['file_path']);
    final digest = await sha256.bind(file.openRead()).last;
    
    if (digest.toString() == session.metadata.hash) {
      await _db.updateFileTransferStatus(session.fileId, FileTransferStatus.completed.index);
      if (session.receivedBitmask != null) {
        await _db.updateFileTransferProgress(session.fileId, session.receivedBitmask!);
      }
      _progressController.add(session);
      _completedController.add(session);
      _addEvent("File received and verified: ${session.metadata.name}");
    } else {
      session.status = FileTransferStatus.failed;
      _progressController.add(session);
      _addEvent("Hash mismatch for ${session.metadata.name}");
    }
  }

  String _sanitizeFileName(String name) {
    // Prevent path traversal and remove risky characters
    var sanitized = p.basename(name);
    sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return sanitized;
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

  void _addEvent(String msg) {
    print("[FileTransfer] $msg");
  }

  Future<String> getTargetDir(bool isWebShare) async {
    // For WebShare, we use the app private storage (safer)
    if (isWebShare) {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'PeerChat', 'WebShare'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }

    // For DirectShare, we use the absolute root: /storage/emulated/0/PeerChat/Downloads
    if (Platform.isAndroid) {
      // Request Manage External Storage permission
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) {
        await Permission.manageExternalStorage.request();
      }

      final dirs = await ExternalPath.getExternalStorageDirectories();
      final root = (dirs != null && dirs.isNotEmpty) ? dirs.first : '/storage/emulated/0';
      final dir = Directory(p.join(root, 'PeerChat', 'Downloads'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } else {
      // Fallback for iOS or other platforms
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'PeerChat', 'DirectShare'));
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir.path;
    }
  }

  Future<void> openFile(String fileId) async {
    final dbRow = await _db.getFileTransfer(fileId);
    if (dbRow != null && dbRow['file_path'] != null) {
      final path = dbRow['file_path'];
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        print("Error opening file: ${result.message}");
      }
    }
  }

  // --- External Controls ---

  void abortTransfer(String fileId) async {
    final session = _activeSessions[fileId];
    if (session == null) return;

    session.status = FileTransferStatus.aborted;
    await _db.updateFileTransferStatus(fileId, FileTransferStatus.aborted.index);
    
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeControl,
      data: Uint8List(1)..[0] = FileTransferControl.abort.index,
    );
    
    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );

    session.close();
    _activeSessions.remove(fileId);
    _progressController.add(session);
  }

  Future<void> resumeTransfer(String fileId) async {
    final dbRow = await _db.getFileTransfer(fileId);
    if (dbRow == null) return;

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
      receivedBitmask: dbRow['received_chunks'],
    );

    _activeSessions[fileId] = session;
    
    // Send sync request
    final payload = FileTransferPayload(
      fileId: fileId,
      typeIndicator: FileTransferPayload.typeResumeSync,
      data: session.receivedBitmask ?? Uint8List(0),
    );

    _router.sendDataMessage(
      recipientPeerId: session.peerId,
      data: payload.toBytes(),
      type: MessageType.fileTransfer,
      priority: MessagePriority.high,
    );
  }

  // --- Queue Management ---
  final List<String> _transferQueue = [];
  static const int maxConcurrentTransfers = 1;

  void _enqueueTransfer(String fileId) {
    if (!_transferQueue.contains(fileId)) {
      _transferQueue.add(fileId);
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
        session.status = FileTransferStatus.transferring;
        _sendNextChunks(session);
        activeCount++;
      }
    }
  }

  Future<void> deleteTransfer(String fileId) async {
    _activeSessions.remove(fileId);
    await _db.deleteFileTransfer(fileId);
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
  RandomAccessFile? fileHandle;
  final bool isIncoming;
  Uint8List? receivedBitmask;
  
  // Sliding Window state
  int unackedBase = 0;
  int nextSeqNum = 0;
  final Set<int> inFlight = {};

  FileTransferSession({
    required this.fileId,
    required this.peerId,
    required this.metadata,
    this.status = FileTransferStatus.requesting,
    this.progress = 0.0,
    required this.isIncoming,
    this.receivedBitmask,
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
    fileHandle?.closeSync();
  }
}
