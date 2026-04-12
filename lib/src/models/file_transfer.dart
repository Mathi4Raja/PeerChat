import 'dart:typed_data';
import 'dart:convert';

enum FileTransferStatus {
  requesting,  // Waiting for peer to accept
  accepted,    // Peer accepted, starting transfer
  rejected,    // Peer rejected
  transferring,// Active data flow
  paused,      // Manually paused
  completed,   // All chunks received and verified
  failed,      // Error occurred (network, disk, hash mismatch)
  aborted      // Manually cancelled
}

enum FileTransferControl {
  accept,
  reject,
  pause,
  resume,
  abort
}

class FileMetadata {
  final String fileId;
  final String name;
  final int size;
  final String type;
  final int totalChunks;
  final String hash; // SHA-256 for final verification

  FileMetadata({
    required this.fileId,
    required this.name,
    required this.size,
    required this.type,
    required this.totalChunks,
    required this.hash,
  });

  Map<String, dynamic> toMap() => {
    'fileId': fileId,
    'name': name,
    'size': size,
    'type': type,
    'totalChunks': totalChunks,
    'hash': hash,
  };

  factory FileMetadata.fromMap(Map<String, dynamic> map) => FileMetadata(
    fileId: map['fileId'],
    name: map['name'],
    size: map['size'],
    type: map['type'] ?? 'application/octet-stream',
    totalChunks: map['totalChunks'],
    hash: map['hash'],
  );
}

/// The payload inside a MeshMessage with type 'fileTransfer'
class FileTransferPayload {
  final String fileId;
  final int typeIndicator; // 0=META, 1=CONTROL, 2=CHUNK, 3=ACK, 4=COMPLETE, 5=RESUME_SYNC
  final Uint8List data;

  FileTransferPayload({
    required this.fileId,
    required this.typeIndicator,
    required this.data,
  });

  static const int typeMeta = 0;
  static const int typeControl = 1;
  static const int typeChunk = 2;
  static const int typeAck = 3;
  static const int typeComplete = 4;
  static const int typeResumeSync = 5;

  Uint8List toBytes() {
    final builder = BytesBuilder();
    final idBytes = utf8.encode(fileId);
    builder.addByte(idBytes.length);
    builder.add(idBytes);
    builder.addByte(typeIndicator);
    builder.add(data);
    return builder.toBytes();
  }

  factory FileTransferPayload.fromBytes(Uint8List bytes) {
    if (bytes.length < 3) throw Exception("Malformed FileTransferPayload: too short");
    int offset = 0;
    final idLen = bytes[offset++];
    
    // Bounds check for fileId
    if (bytes.length < offset + idLen + 1) {
      throw Exception("Malformed FileTransferPayload: missing ID or Type");
    }
    
    final fileId = utf8.decode(bytes.sublist(offset, offset + idLen));
    offset += idLen;
    
    final typeIndicator = bytes[offset++];
    
    // Remaining bytes are data
    final data = bytes.sublist(offset);
    
    return FileTransferPayload(
      fileId: fileId,
      typeIndicator: typeIndicator,
      data: data,
    );
  }
}

class FileChunk {
  final int index;
  final Uint8List data;

  FileChunk({required this.index, required this.data});

  Uint8List toBytes() {
    final builder = BytesBuilder();
    builder.add(uint32ToBytes(index));
    builder.add(data);
    return builder.toBytes();
  }

  factory FileChunk.fromBytes(Uint8List bytes) {
    if (bytes.length < 4) throw Exception("Malformed FileChunk: missing index");
    
    final index = bytesToUint32(bytes.sublist(0, 4));
    
    // Ensure data exists beyond index
    final data = bytes.length > 4 ? bytes.sublist(4) : Uint8List(0);
    
    return FileChunk(index: index, data: data);
  }

  static Uint8List uint32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = (value >> 24) & 0xFF
      ..[1] = (value >> 16) & 0xFF
      ..[2] = (value >> 8) & 0xFF
      ..[3] = value & 0xFF;
  }

  static int bytesToUint32(Uint8List bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }
}
