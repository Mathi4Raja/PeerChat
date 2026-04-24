import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/chat_message.dart';

void main() {
  group('ChatMessage', () {
    test('toMap/fromMap roundtrip with reply and hop metadata', () {
      final msg = ChatMessage(
        id: 'id',
        peerId: 'peer',
        content: 'hello',
        timestamp: 10,
        isSentByMe: true,
        status: MessageStatus.queued,
        isRead: false,
        hopCount: 2,
        replyToMessageId: 'r1',
        replyToContent: 'quoted',
        replyToPeerId: 'p1',
      );

      final from = ChatMessage.fromMap(msg.toMap());
      expect(from.id, msg.id);
      expect(from.status, MessageStatus.queued);
      expect(from.isRead, isFalse);
      expect(from.hopCount, 2);
      expect(from.replyToMessageId, 'r1');
      expect(from.replyToContent, 'quoted');
      expect(from.replyToPeerId, 'p1');
    });

    test('fromMap defaults read state and normalizes numeric hopCount', () {
      final from = ChatMessage.fromMap({
        'id': '1',
        'peerId': 'p',
        'content': 'x',
        'timestamp': 1,
        'isSentByMe': 0,
        'status': MessageStatus.sent.index,
        'hopCount': 3.9,
      });
      expect(from.isRead, isTrue);
      expect(from.hopCount, 3);
    });
  });

  group('MessageStatusUI', () {
    test('failed status uses error icon and red color', () {
      expect(MessageStatus.failed.icon, Icons.error_outline_rounded);
      expect(MessageStatus.failed.color, const Color(0xFFEF5350));
    });

    test('non-failed statuses map to expected icons', () {
      expect(MessageStatus.sending.icon, Icons.access_time_rounded);
      expect(MessageStatus.queued.icon, Icons.schedule_send_rounded);
      expect(MessageStatus.routing.icon, Icons.alt_route_rounded);
      expect(MessageStatus.sent.icon, Icons.alt_route_rounded);
    });
  });
}

