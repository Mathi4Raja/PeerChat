import 'dart:typed_data';
import 'dart:convert';
import '../config/limits_config.dart';

enum MessageType {
  data,
  routeRequest,
  routeResponse,
  connectionUpgradeRequest,
  connectionUpgradeResponse,
  fileTransfer,
}


enum MessagePriority {
  high,
  normal,
  low,
}

class MeshMessage {
  final String messageId;
  final MessageType type;
  final String senderPeerId;
  final String recipientPeerId;
  final int ttl;
  final int hopCount;
  final MessagePriority priority;
  final int timestamp;
  final Uint8List? encryptedContent;
  final Uint8List signature;

  /// Duration in milliseconds before this message expires.
  /// Uses duration-based checking (clock-independent):
  ///   age = now - timestamp; if (age > expiryDuration) → expired
  final int expiryDuration;

  /// Default expiry: 7 days in milliseconds.
  static const int defaultExpiryDuration =
      MessageLimits.defaultExpiryDurationMs;

  MeshMessage({
    required this.messageId,
    required this.type,
    required this.senderPeerId,
    required this.recipientPeerId,
    required this.ttl,
    required this.hopCount,
    required this.priority,
    required this.timestamp,
    this.encryptedContent,
    required this.signature,
    this.expiryDuration = defaultExpiryDuration,
  });

  /// Check if this message has expired using clock-independent duration.
  bool get isExpired {
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    return age > expiryDuration;
  }

  MeshMessage copyWithSignature(Uint8List signature) {
    return MeshMessage(
      messageId: messageId,
      type: type,
      senderPeerId: senderPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl,
      hopCount: hopCount,
      priority: priority,
      timestamp: timestamp,
      expiryDuration: expiryDuration,
      encryptedContent: encryptedContent,
      signature: signature,
    );
  }

  // Serialize to bytes for transmission
  Uint8List toBytes() {
    final buffer = BytesBuilder();

    // Message ID (fixed-width wire ID)
    buffer.add(utf8.encode(_fixedWidthId(messageId)));

    // Type (1 byte)
    buffer.addByte(type.index);

    // Sender peer ID length (2 bytes) + sender peer ID
    final senderBytes = utf8.encode(senderPeerId);
    buffer.add(_uint16ToBytes(senderBytes.length));
    buffer.add(senderBytes);

    // Recipient peer ID length (2 bytes) + recipient peer ID
    final recipientBytes = utf8.encode(recipientPeerId);
    buffer.add(_uint16ToBytes(recipientBytes.length));
    buffer.add(recipientBytes);

    // TTL (1 byte)
    buffer.addByte(ttl);

    // Hop count (1 byte)
    buffer.addByte(hopCount);

    // Priority (1 byte)
    buffer.addByte(priority.index);

    // Timestamp (8 bytes)
    buffer.add(_uint64ToBytes(timestamp));

    // Encrypted content length (4 bytes) + encrypted content
    if (encryptedContent != null) {
      buffer.add(_uint32ToBytes(encryptedContent!.length));
      buffer.add(encryptedContent!);
    } else {
      buffer.add(_uint32ToBytes(0));
    }

    // Signature length (2 bytes) + signature
    buffer.add(_uint16ToBytes(signature.length));
    buffer.add(signature);

    // Expiry duration (8 bytes) — appended at end for backward compatibility
    buffer.add(_uint64ToBytes(expiryDuration));

    return buffer.toBytes();
  }

  // Deserialize from bytes
  static MeshMessage fromBytes(Uint8List bytes) {
    int offset = 0;

    // Message ID (fixed-width wire ID)
    final messageId = utf8
        .decode(bytes.sublist(offset, offset + MessageLimits.wireIdLength))
        .trim();
    offset += MessageLimits.wireIdLength;

    // Type (1 byte)
    final type = MessageType.values[bytes[offset]];
    offset += 1;

    // Sender peer ID
    final senderLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final senderPeerId =
        utf8.decode(bytes.sublist(offset, offset + senderLength));
    offset += senderLength;

    // Recipient peer ID
    final recipientLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final recipientPeerId =
        utf8.decode(bytes.sublist(offset, offset + recipientLength));
    offset += recipientLength;

    // TTL (1 byte)
    final ttl = bytes[offset];
    offset += 1;

    // Hop count (1 byte)
    final hopCount = bytes[offset];
    offset += 1;

    // Priority (1 byte)
    final priority = MessagePriority.values[bytes[offset]];
    offset += 1;

    // Timestamp (8 bytes)
    final timestamp = _bytesToUint64(bytes.sublist(offset, offset + 8));
    offset += 8;

    // Encrypted content
    final contentLength = _bytesToUint32(bytes.sublist(offset, offset + 4));
    offset += 4;
    Uint8List? encryptedContent;
    if (contentLength > 0) {
      encryptedContent = bytes.sublist(offset, offset + contentLength);
      offset += contentLength;
    }

    // Signature
    final signatureLength = _bytesToUint16(bytes.sublist(offset, offset + 2));
    offset += 2;
    final signature = bytes.sublist(offset, offset + signatureLength);
    offset += signatureLength;

    // Expiry duration (8 bytes, optional for backward compatibility)
    int expiryDuration = MeshMessage.defaultExpiryDuration;
    if (offset + 8 <= bytes.length) {
      expiryDuration = _bytesToUint64(bytes.sublist(offset, offset + 8));
      // offset += 8; // no more fields after this
    }

    return MeshMessage(
      messageId: messageId,
      type: type,
      senderPeerId: senderPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl,
      hopCount: hopCount,
      priority: priority,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: signature,
      expiryDuration: expiryDuration,
    );
  }

  // Create bytes for signing (excludes signature field).
  // Important: routing-mutated fields (ttl, hopCount) are intentionally omitted
  // so a relay can decrement/increment them without invalidating origin signature.
  Uint8List toBytesForSigning() {
    final buffer = BytesBuilder();

    buffer.add(utf8.encode(_fixedWidthId(messageId)));
    buffer.addByte(type.index);

    final senderBytes = utf8.encode(senderPeerId);
    buffer.add(_uint16ToBytes(senderBytes.length));
    buffer.add(senderBytes);

    final recipientBytes = utf8.encode(recipientPeerId);
    buffer.add(_uint16ToBytes(recipientBytes.length));
    buffer.add(recipientBytes);

    buffer.addByte(priority.index);
    buffer.add(_uint64ToBytes(timestamp));

    if (encryptedContent != null) {
      buffer.add(_uint32ToBytes(encryptedContent!.length));
      buffer.add(encryptedContent!);
    } else {
      buffer.add(_uint32ToBytes(0));
    }

    return buffer.toBytes();
  }

  // Legacy signing payload kept for backward verification compatibility.
  Uint8List toBytesForSigningLegacy() {
    final buffer = BytesBuilder();

    buffer.add(utf8.encode(_fixedWidthId(messageId)));
    buffer.addByte(type.index);

    final senderBytes = utf8.encode(senderPeerId);
    buffer.add(_uint16ToBytes(senderBytes.length));
    buffer.add(senderBytes);

    final recipientBytes = utf8.encode(recipientPeerId);
    buffer.add(_uint16ToBytes(recipientBytes.length));
    buffer.add(recipientBytes);

    buffer.addByte(ttl);
    buffer.addByte(hopCount);
    buffer.addByte(priority.index);
    buffer.add(_uint64ToBytes(timestamp));

    if (encryptedContent != null) {
      buffer.add(_uint32ToBytes(encryptedContent!.length));
      buffer.add(encryptedContent!);
    } else {
      buffer.add(_uint32ToBytes(0));
    }

    return buffer.toBytes();
  }

  // Create a copy with updated TTL and hop count for forwarding
  MeshMessage copyForForwarding() {
    return MeshMessage(
      messageId: messageId,
      type: type,
      senderPeerId: senderPeerId,
      recipientPeerId: recipientPeerId,
      ttl: ttl - 1,
      hopCount: hopCount + 1,
      priority: priority,
      timestamp: timestamp,
      encryptedContent: encryptedContent,
      signature: signature,
      expiryDuration: expiryDuration,
    );
  }

  // Helper methods for byte conversion
  static Uint8List _uint16ToBytes(int value) {
    return Uint8List(2)
      ..[0] = (value >> 8) & 0xFF
      ..[1] = value & 0xFF;
  }

  static int _bytesToUint16(Uint8List bytes) {
    return (bytes[0] << 8) | bytes[1];
  }

  static Uint8List _uint32ToBytes(int value) {
    return Uint8List(4)
      ..[0] = (value >> 24) & 0xFF
      ..[1] = (value >> 16) & 0xFF
      ..[2] = (value >> 8) & 0xFF
      ..[3] = value & 0xFF;
  }

  static int _bytesToUint32(Uint8List bytes) {
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
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

  /// Mesh wire format currently expects fixed-width 36-char IDs.
  static String _fixedWidthId(String id) {
    if (id.length >= MessageLimits.wireIdLength) {
      return id.substring(0, MessageLimits.wireIdLength);
    }
    return id.padRight(MessageLimits.wireIdLength);
  }
}
