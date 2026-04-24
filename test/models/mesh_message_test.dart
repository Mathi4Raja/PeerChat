import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/mesh_message.dart';

MeshMessage _message({
  required String id,
  int? ttl,
  int? hopCount,
  int? timestamp,
  Uint8List? encryptedContent,
  Uint8List? signature,
  int? expiryDuration,
}) {
  return MeshMessage(
    messageId: id,
    type: MessageType.data,
    senderPeerId: 'sender',
    recipientPeerId: 'recipient',
    ttl: ttl ?? 8,
    hopCount: hopCount ?? 1,
    priority: MessagePriority.normal,
    timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    encryptedContent: encryptedContent,
    signature: signature ?? Uint8List.fromList([1, 2, 3]),
    expiryDuration: expiryDuration ?? MeshMessage.defaultExpiryDuration,
  );
}

void main() {
  group('MeshMessage', () {
    test('serializes and deserializes with encrypted content', () {
      final msg = _message(
        id: '12345678-1234-1234-1234-123456789012',
        encryptedContent: Uint8List.fromList([10, 11, 12]),
        expiryDuration: 2222,
      );

      final bytes = msg.toBytes();
      final decoded = MeshMessage.fromBytes(bytes);

      expect(decoded.messageId, msg.messageId);
      expect(decoded.senderPeerId, msg.senderPeerId);
      expect(decoded.recipientPeerId, msg.recipientPeerId);
      expect(decoded.ttl, msg.ttl);
      expect(decoded.hopCount, msg.hopCount);
      expect(decoded.priority, msg.priority);
      expect(decoded.timestamp, msg.timestamp);
      expect(decoded.encryptedContent, msg.encryptedContent);
      expect(decoded.signature, msg.signature);
      expect(decoded.expiryDuration, 2222);
    });

    test('deserializes legacy bytes without expiry duration', () {
      final msg = _message(id: 'legacy-id');
      final bytes = msg.toBytes();
      final legacyBytes = bytes.sublist(0, bytes.length - 8);
      final decoded = MeshMessage.fromBytes(legacyBytes);

      expect(decoded.expiryDuration, MeshMessage.defaultExpiryDuration);
    });

    test('copyWithSignature and copyForForwarding preserve expected fields', () {
      final msg = _message(id: 'msg-1', ttl: 5, hopCount: 2);
      final signed = msg.copyWithSignature(Uint8List.fromList([9]));
      final forwarded = msg.copyForForwarding();

      expect(signed.signature, Uint8List.fromList([9]));
      expect(signed.ttl, msg.ttl);
      expect(signed.hopCount, msg.hopCount);

      expect(forwarded.ttl, 4);
      expect(forwarded.hopCount, 3);
      expect(forwarded.signature, msg.signature);
      expect(forwarded.expiryDuration, msg.expiryDuration);
    });

    test('signing bytes are stable across ttl and hop changes', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final a = _message(
        id: 'signing-id',
        ttl: 8,
        hopCount: 1,
        timestamp: now,
        encryptedContent: Uint8List.fromList([1, 2]),
      );
      final b = _message(
        id: 'signing-id',
        ttl: 3,
        hopCount: 9,
        timestamp: now,
        encryptedContent: Uint8List.fromList([1, 2]),
      );

      expect(a.toBytesForSigning(), b.toBytesForSigning());
      expect(a.toBytesForSigningLegacy(), isNot(equals(b.toBytesForSigningLegacy())));
    });

    test('isExpired uses duration-based expiry', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fresh = _message(id: 'fresh', timestamp: now - 100, expiryDuration: 5000);
      final old = _message(id: 'old', timestamp: now - 10000, expiryDuration: 5000);

      expect(fresh.isExpired, isFalse);
      expect(old.isExpired, isTrue);
    });

    test('wire ID is fixed width and trimmed on deserialize', () {
      final longId = 'x' * 50;
      final msg = _message(id: longId);
      final decoded = MeshMessage.fromBytes(msg.toBytes());
      expect(decoded.messageId.length, 36);
      expect(decoded.messageId, 'x' * 36);
    });
  });
}
