import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/mesh_message.dart';
import 'package:peerchat_secure/src/models/queued_message.dart';

MeshMessage _msg({required int timestamp, int? expiryDuration}) {
  return MeshMessage(
    messageId: 'msg-1',
    type: MessageType.data,
    senderPeerId: 's',
    recipientPeerId: 'r',
    ttl: 8,
    hopCount: 0,
    priority: MessagePriority.high,
    timestamp: timestamp,
    signature: Uint8List.fromList([1]),
    expiryDuration: expiryDuration ?? 5000,
  );
}

void main() {
  group('QueuedMessage', () {
    test('toMap computes expiry when explicit expiryTime is absent', () {
      final message = _msg(timestamp: 1000, expiryDuration: 9000);
      final queued = QueuedMessage(
        message: message,
        nextHopPeerId: 'hop',
        queuedTimestamp: 2000,
        origin: QueueOrigin.mesh,
      );

      final map = queued.toMap();
      expect(map['expiry_time'], 10000);
      expect(map['origin_type'], QueueOrigin.mesh.index);
    });

    test('fromMap handles invalid origin and copyWith overrides values', () {
      final message = _msg(timestamp: DateTime.now().millisecondsSinceEpoch);
      final base = QueuedMessage(
        message: message,
        nextHopPeerId: 'hop',
        queuedTimestamp: 2000,
        origin: QueueOrigin.local,
      );
      final map = base.toMap();
      map['origin_type'] = -1;
      map['attempt_count'] = 3;
      map['next_retry_time'] = 4444;

      final from = QueuedMessage.fromMap(map);
      final copied = from.copyWith(
        attemptCount: 55,
        nextHopPeerId: 'h2',
      );

      expect(from.origin, QueueOrigin.local);
      expect(from.attemptCount, 3);
      expect(from.nextRetryTime, 4444);
      expect(copied.attemptCount, 55);
      expect(copied.nextHopPeerId, 'h2');
    });

    test('shouldDrop and isExpired reflect message state', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final oldMessage = _msg(timestamp: now - 9999, expiryDuration: 1000);
      final queued = QueuedMessage(
        message: oldMessage,
        nextHopPeerId: 'hop',
        queuedTimestamp: now,
        origin: QueueOrigin.local,
        attemptCount: QueuedMessage.maxRetries + 1,
      );

      expect(queued.shouldDrop, isTrue);
      expect(queued.isExpired, isTrue);
    });
  });
}

