import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/chat_payload.dart';

void main() {
  group('ChatPayload', () {
    test('toWire returns plain text when no reply metadata exists', () {
      const payload = ChatPayload(text: 'hello');
      expect(payload.hasReply, isFalse);
      expect(payload.toWire(), 'hello');
    });

    test('toWire encodes reply metadata and decode restores it', () {
      const payload = ChatPayload(
        text: 'hello',
        replyToMessageId: ' m-1 ',
        replyToContent: ' quoted text ',
        replyToPeerId: ' p-1 ',
      );

      final wire = payload.toWire();
      final decodedMap = jsonDecode(wire) as Map<String, dynamic>;
      expect(decodedMap['k'], 'pc_chat');
      expect(decodedMap['v'], 1);
      expect(decodedMap['t'], 'hello');

      final decoded = ChatPayload.decode(wire);
      expect(decoded.text, 'hello');
      expect(decoded.replyToMessageId, 'm-1');
      expect(decoded.replyToContent, 'quoted text');
      expect(decoded.replyToPeerId, 'p-1');
      expect(decoded.hasReply, isTrue);
    });

    test('decode falls back to raw text for malformed or unsupported payloads', () {
      expect(ChatPayload.decode('not-json').text, 'not-json');
      expect(ChatPayload.decode('["x"]').text, '["x"]');
      expect(ChatPayload.decode('{"k":"other","v":1,"t":"x"}').text, '{"k":"other","v":1,"t":"x"}');
      expect(ChatPayload.decode('{"k":"pc_chat","v":1,"t":42}').text, '{"k":"pc_chat","v":1,"t":42}');
    });
  });
}
