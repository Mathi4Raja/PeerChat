import 'dart:typed_data';

/// State machine for file transfer lifecycle.
enum FileTransferState {
  /// Transfer initiated, waiting for acceptance.
  pending,
  /// Receiver accepted, chunks being transmitted.
  transferring,
  /// All chunks sent/received, waiting for integrity check.
  verifying,
  /// Transfer complete, file validated.
  completed,
  /// Transfer failed or rejected.
  failed,
  /// Transfer paused (e.g., transport switch).
  paused,
  /// Transfer cancelled by user.
  cancelled,
}

/// Direction of transfer from this device's perspective.
enum TransferDirection {
  sending,
  receiving,
}

/// Types of file transfer protocol messages.
enum FileTransferMessageType {
  /// Sender → Receiver: file metadata + SHA-256
  fileMeta,
  /// Receiver → Sender: accept/reject
  fileAccept,
  /// Receiver → Sender: reject transfer
  fileReject,
  /// Sender → Receiver: a chunk of file data
  chunk,
  /// Receiver → Sender: cumulative ACK (highestContiguousChunkIndex)
  chunkAck,
  /// Sender/Receiver: transfer complete
  fileComplete,
  /// Either direction: resume from specific chunk
  resumeFrom,
  /// Either direction: cancel transfer
  cancelTransfer,
}

/// Metadata about a file being transferred.
class FileMetadata {
  final String fileId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final Uint8List sha256Hash;
  final int totalChunks;

  /// Chunk size in bytes (default 64KB).
  static const int chunkSize = 65536;

  FileMetadata({
    required this.fileId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.sha256Hash,
    required this.totalChunks,
  });

  Map<String, dynamic> toMap() => {
    'fileId': fileId,
    'fileName': fileName,
    'fileSize': fileSize,
    'mimeType': mimeType,
    'sha256Hash': sha256Hash,
    'totalChunks': totalChunks,
  };

  factory FileMetadata.fromMap(Map<String, dynamic> map) => FileMetadata(
    fileId: map['fileId'] as String,
    fileName: map['fileName'] as String,
    fileSize: map['fileSize'] as int,
    mimeType: map['mimeType'] as String,
    sha256Hash: map['sha256Hash'] as Uint8List,
    totalChunks: map['totalChunks'] as int,
  );
}

/// Tracks the state of a chunk using a bitset for ordering.
class ChunkTracker {
  final int totalChunks;
  /// Bitset: bit i = 1 means chunk i has been received.
  final List<bool> _received;

  ChunkTracker(this.totalChunks) : _received = List.filled(totalChunks, false);

  /// Mark a chunk as received.
  void markReceived(int index) {
    if (index >= 0 && index < totalChunks) {
      _received[index] = true;
    }
  }

  /// Check if a chunk has been received.
  bool isReceived(int index) {
    if (index < 0 || index >= totalChunks) return false;
    return _received[index];
  }

  /// Get the highest contiguous chunk index (for cumulative ACK).
  /// Returns -1 if no chunks received, or the highest index where
  /// all chunks 0..index have been received.
  int get highestContiguous {
    for (int i = 0; i < totalChunks; i++) {
      if (!_received[i]) return i - 1;
    }
    return totalChunks - 1;
  }

  /// Check if all chunks have been received.
  bool get isComplete => _received.every((r) => r);

  /// Count of received chunks.
  int get receivedCount => _received.where((r) => r).length;

  /// Get list of missing chunk indices.
  List<int> get missingChunks {
    final missing = <int>[];
    for (int i = 0; i < totalChunks; i++) {
      if (!_received[i]) missing.add(i);
    }
    return missing;
  }
}

/// Active file transfer session state.
class FileTransferSession {
  final String fileId;
  final String peerId;
  final FileMetadata metadata;
  final TransferDirection direction;
  FileTransferState state;
  final ChunkTracker chunkTracker;

  /// Path to temp file (partial download) or source file (upload).
  String? filePath;

  /// Sliding window: indices of chunks currently in-flight (sent but not ACKed).
  final Set<int> inFlightChunks = {};
  static const int maxInFlight = 5;

  /// Retry count per chunk for ACK timeouts.
  final Map<int, int> chunkRetryCount = {};
  static const int maxChunkRetries = 5;

  /// Timestamps for ACK timeout tracking.
  final Map<int, int> chunkSentTimestamp = {};

  /// ACK timeout in milliseconds (varies by transport).
  int ackTimeoutMs;

  /// Last activity timestamp for stale detection.
  int lastActivityTimestamp;

  /// Transfer start time for progress tracking.
  final int startTimestamp;

  FileTransferSession({
    required this.fileId,
    required this.peerId,
    required this.metadata,
    required this.direction,
    this.state = FileTransferState.pending,
    this.filePath,
    this.ackTimeoutMs = 10000, // Default 10s for WiFi
  }) : chunkTracker = ChunkTracker(metadata.totalChunks),
       lastActivityTimestamp = DateTime.now().millisecondsSinceEpoch,
       startTimestamp = DateTime.now().millisecondsSinceEpoch;

  /// Check if the sliding window has room for more chunks.
  bool get canSendMore => inFlightChunks.length < maxInFlight;

  /// Get next chunk index to send (after highest contiguous ACK).
  int? get nextChunkToSend {
    for (int i = 0; i < metadata.totalChunks; i++) {
      if (!chunkTracker.isReceived(i) && !inFlightChunks.contains(i)) {
        return i;
      }
    }
    return null;
  }

  /// Progress percentage.
  double get progress => metadata.totalChunks > 0
      ? chunkTracker.receivedCount / metadata.totalChunks
      : 0.0;

  /// For DB persistence (crash recovery).
  Map<String, dynamic> toMap() => {
    'file_id': fileId,
    'peer_id': peerId,
    'file_name': metadata.fileName,
    'file_size': metadata.fileSize,
    'mime_type': metadata.mimeType,
    'sha256_hash': metadata.sha256Hash,
    'total_chunks': metadata.totalChunks,
    'received_chunks': chunkTracker.receivedCount,
    'direction': direction.index,
    'state': state.index,
    'file_path': filePath,
    'ack_timeout_ms': ackTimeoutMs,
    'last_activity': lastActivityTimestamp,
    'start_timestamp': startTimestamp,
  };
}
