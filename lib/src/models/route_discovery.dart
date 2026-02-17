import 'dart:typed_data';
import 'dart:convert';

class RouteRequest {
  final String requestId;
  final String requestorPeerId;
  final String targetPeerId;
  final int ttl;
  final int timestamp;
  final Uint8List signature;

  RouteRequest({
    required this.requestId,
    required this.requestorPeerId,
    required this.targetPeerId,
    required this.ttl,
    required this.timestamp,
    required this.signature,
  });

  // Serialize to bytes
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    
    // Request ID (36 bytes for UUID string)
    buffer.add(utf8.encode(requestId.padRight(36)));
    
    // Requestor peer ID length (2 bytes) + requestor peer ID
    final requestorBytes = utf8.encode(requestorPeerId);
    buffer.add(_uint16ToBytes(requestorBytes.length));
    buffer.add(requestorBytes);
    
    // Target peer ID length (2 bytes) + target peer ID
    final targetBytes = utf8.encode(targetPeerId);
    buffer.add(_uint16ToBytes(targetBytes.length));
    buffer.add(targetBytes);
    
    // TTL (1 byte)
    buffer.addByte(ttl);
    
    // Timestamp (8 bytes)
    buffer.add(_uint64ToBytes(timestamp));
    
    // Signature length (2 bytes) + signature
    buffer.add(_uint16ToBytes(signature.length));
    buffer.add(signature);
    
    return buffer.toBytes();
  }

  // Deserialize from bytes
  static RouteRequest fromBytes(Uint8List bytes) {
    int offset = 0;
    
    // Request ID (36 bytes)
    final requestId = utf8.decode(bytes.sublist(offset, offset + 36)).trim();
    offset += 36;
    
    // Requestor peer ID
    final requestorLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final requestorPeerId = utf8.decode(bytes.sublist(offset, offset + requestorLength));
    offset += requestorLength;
    
    // Target peer ID
    final targetLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final targetPeerId = utf8.decode(bytes.sublist(offset, offset + targetLength));
    offset += targetLength;
    
    // TTL (1 byte)
    final ttl = bytes[offset];
    offset += 1;
    
    // Timestamp (8 bytes)
    final timestamp = _bytesToUint64(bytes.sublist(offset, offset + 8));
    offset += 8;
    
    // Signature
    final signatureLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final signature = bytes.sublist(offset, offset + signatureLength);
    
    return RouteRequest(
      requestId: requestId,
      requestorPeerId: requestorPeerId,
      targetPeerId: targetPeerId,
      ttl: ttl,
      timestamp: timestamp,
      signature: signature,
    );
  }

  // Create bytes for signing (excludes signature field)
  Uint8List toBytesForSigning() {
    final buffer = BytesBuilder();
    
    buffer.add(utf8.encode(requestId.padRight(36)));
    
    final requestorBytes = utf8.encode(requestorPeerId);
    buffer.add(_uint16ToBytes(requestorBytes.length));
    buffer.add(requestorBytes);
    
    final targetBytes = utf8.encode(targetPeerId);
    buffer.add(_uint16ToBytes(targetBytes.length));
    buffer.add(targetBytes);
    
    buffer.addByte(ttl);
    buffer.add(_uint64ToBytes(timestamp));
    
    return buffer.toBytes();
  }

  // Helper methods
  static Uint8List _uint16ToBytes(int value) {
    return Uint8List(2)
      ..[0] = (value >> 8) & 0xFF
      ..[1] = value & 0xFF;
  }

  static int _bytesToUint16(Uint8List bytes) {
    return (bytes[0] << 8) | bytes[1];
  }

  static Uint8List _uint64ToBytes(int value) {
    return Uint8List(8)
      ..[0] = (value >> 56) & 0xFF
      ..[1] = (value >> 48) & 0xFF
      ..[2] = (value >> 40) & 0xFF
      ..[3] = (value >> 32) & 0xFF
      ..[4] = (value >> 24) & 0xFF
      ..[5] = (value >> 16) & 0xFF
      ..[6] = (value >> 8) & 0xFF
      ..[7] = value & 0xFF;
  }

  static int _bytesToUint64(Uint8List bytes) {
    return (bytes[0] << 56) |
        (bytes[1] << 48) |
        (bytes[2] << 40) |
        (bytes[3] << 32) |
        (bytes[4] << 24) |
        (bytes[5] << 16) |
        (bytes[6] << 8) |
        bytes[7];
  }
}

class RouteResponse {
  final String requestId;
  final String responderPeerId;
  final String targetPeerId;
  final int hopCount;
  final int timestamp;
  final Uint8List signature;

  RouteResponse({
    required this.requestId,
    required this.responderPeerId,
    required this.targetPeerId,
    required this.hopCount,
    required this.timestamp,
    required this.signature,
  });

  // Serialize to bytes
  Uint8List toBytes() {
    final buffer = BytesBuilder();
    
    // Request ID (36 bytes for UUID string)
    buffer.add(utf8.encode(requestId.padRight(36)));
    
    // Responder peer ID length (2 bytes) + responder peer ID
    final responderBytes = utf8.encode(responderPeerId);
    buffer.add(_uint16ToBytes(responderBytes.length));
    buffer.add(responderBytes);
    
    // Target peer ID length (2 bytes) + target peer ID
    final targetBytes = utf8.encode(targetPeerId);
    buffer.add(_uint16ToBytes(targetBytes.length));
    buffer.add(targetBytes);
    
    // Hop count (1 byte)
    buffer.addByte(hopCount);
    
    // Timestamp (8 bytes)
    buffer.add(_uint64ToBytes(timestamp));
    
    // Signature length (2 bytes) + signature
    buffer.add(_uint16ToBytes(signature.length));
    buffer.add(signature);
    
    return buffer.toBytes();
  }

  // Deserialize from bytes
  static RouteResponse fromBytes(Uint8List bytes) {
    int offset = 0;
    
    // Request ID (36 bytes)
    final requestId = utf8.decode(bytes.sublist(offset, offset + 36)).trim();
    offset += 36;
    
    // Responder peer ID
    final responderLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final responderPeerId = utf8.decode(bytes.sublist(offset, offset + responderLength));
    offset += responderLength;
    
    // Target peer ID
    final targetLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final targetPeerId = utf8.decode(bytes.sublist(offset, offset + targetLength));
    offset += targetLength;
    
    // Hop count (1 byte)
    final hopCount = bytes[offset];
    offset += 1;
    
    // Timestamp (8 bytes)
    final timestamp = _bytesToUint64(bytes.sublist(offset, offset + 8));
    offset += 8;
    
    // Signature
    final signatureLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final signature = bytes.sublist(offset, offset + signatureLength);
    
    return RouteResponse(
      requestId: requestId,
      responderPeerId: responderPeerId,
      targetPeerId: targetPeerId,
      hopCount: hopCount,
      timestamp: timestamp,
      signature: signature,
    );
  }

  // Create bytes for signing (excludes signature field)
  Uint8List toBytesForSigning() {
    final buffer = BytesBuilder();
    
    buffer.add(utf8.encode(requestId.padRight(36)));
    
    final responderBytes = utf8.encode(responderPeerId);
    buffer.add(_uint16ToBytes(responderBytes.length));
    buffer.add(responderBytes);
    
    final targetBytes = utf8.encode(targetPeerId);
    buffer.add(_uint16ToBytes(targetBytes.length));
    buffer.add(targetBytes);
    
    buffer.addByte(hopCount);
    buffer.add(_uint64ToBytes(timestamp));
    
    return buffer.toBytes();
  }

  // Helper methods
  static Uint8List _uint16ToBytes(int value) {
    return Uint8List(2)
      ..[0] = (value >> 8) & 0xFF
      ..[1] = value & 0xFF;
  }

  static int _bytesToUint16(Uint8List bytes) {
    return (bytes[0] << 8) | bytes[1];
  }

  static Uint8List _uint64ToBytes(int value) {
    return Uint8List(8)
      ..[0] = (value >> 56) & 0xFF
      ..[1] = (value >> 48) & 0xFF
      ..[2] = (value >> 40) & 0xFF
      ..[3] = (value >> 32) & 0xFF
      ..[4] = (value >> 24) & 0xFF
      ..[5] = (value >> 16) & 0xFF
      ..[6] = (value >> 8) & 0xFF
      ..[7] = value & 0xFF;
  }

  static int _bytesToUint64(Uint8List bytes) {
    return (bytes[0] << 56) |
        (bytes[1] << 48) |
        (bytes[2] << 40) |
        (bytes[3] << 32) |
        (bytes[4] << 24) |
        (bytes[5] << 16) |
        (bytes[6] << 8) |
        bytes[7];
  }
}
