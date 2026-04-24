import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/handshake_message.dart';

void main() {
  group('HandshakeMessage', () {
    test('toBytes and fromBytes roundtrip', () {
      final message = HandshakeMessage(
        peerId: 'peer',
        publicKey: Uint8List.fromList([1, 2, 3]),
        encryptionPublicKey: Uint8List.fromList([4, 5, 6]),
        displayName: 'Peer',
        runtimeProfile: 'normal_direct',
        timestamp: 12345,
      );

      final decoded = HandshakeMessage.fromBytes(message.toBytes());
      expect(decoded, isNotNull);
      expect(decoded!.peerId, 'peer');
      expect(decoded.publicKey, Uint8List.fromList([1, 2, 3]));
      expect(decoded.encryptionPublicKey, Uint8List.fromList([4, 5, 6]));
      expect(decoded.displayName, 'Peer');
      expect(decoded.runtimeProfile, 'normal_direct');
      expect(decoded.timestamp, 12345);
    });

    test('fromBytes defaults runtimeProfile when absent', () {
      final json = jsonEncode({
        'type': 'handshake',
        'peerId': 'peer',
        'publicKey': base64Encode([1]),
        'encryptionPublicKey': base64Encode([2]),
        'displayName': 'Peer',
        'timestamp': 1,
      });
      final decoded = HandshakeMessage.fromBytes(Uint8List.fromList(utf8.encode(json)));
      expect(decoded, isNotNull);
      expect(decoded!.runtimeProfile, 'normal_direct');
    });

    test('fromBytes returns null for wrong type and malformed input', () {
      final wrongType = jsonEncode({'type': 'other'});
      expect(
        HandshakeMessage.fromBytes(Uint8List.fromList(utf8.encode(wrongType))),
        isNull,
      );
      expect(
        HandshakeMessage.fromBytes(Uint8List.fromList([1, 2, 3])),
        isNull,
      );
    });
  });
}

