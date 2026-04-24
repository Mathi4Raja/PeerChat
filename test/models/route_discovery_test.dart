import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/route_discovery.dart';

void main() {
  group('RouteRequest', () {
    test('toBytes/fromBytes roundtrip', () {
      final req = RouteRequest(
        requestId: '12345678-1234-1234-1234-123456789012',
        requestorPeerId: 'req',
        targetPeerId: 'target',
        ttl: 7,
        timestamp: 99,
        signature: Uint8List.fromList([9, 9]),
      );

      final decoded = RouteRequest.fromBytes(req.toBytes());
      expect(decoded.requestId, req.requestId);
      expect(decoded.requestorPeerId, 'req');
      expect(decoded.targetPeerId, 'target');
      expect(decoded.ttl, 7);
      expect(decoded.timestamp, 99);
      expect(decoded.signature, Uint8List.fromList([9, 9]));
    });

    test('toBytesForSigning is independent of signature', () {
      final a = RouteRequest(
        requestId: 'id',
        requestorPeerId: 'req',
        targetPeerId: 'target',
        ttl: 4,
        timestamp: 1,
        signature: Uint8List.fromList([1]),
      );
      final b = RouteRequest(
        requestId: 'id',
        requestorPeerId: 'req',
        targetPeerId: 'target',
        ttl: 4,
        timestamp: 1,
        signature: Uint8List.fromList([2, 3]),
      );
      expect(a.toBytesForSigning(), b.toBytesForSigning());
    });
  });

  group('RouteResponse', () {
    test('toBytes/fromBytes roundtrip', () {
      final res = RouteResponse(
        requestId: '12345678-1234-1234-1234-123456789012',
        responderPeerId: 'resp',
        targetPeerId: 'target',
        hopCount: 3,
        timestamp: 45,
        signature: Uint8List.fromList([7]),
      );

      final decoded = RouteResponse.fromBytes(res.toBytes());
      expect(decoded.requestId, res.requestId);
      expect(decoded.responderPeerId, 'resp');
      expect(decoded.targetPeerId, 'target');
      expect(decoded.hopCount, 3);
      expect(decoded.timestamp, 45);
      expect(decoded.signature, Uint8List.fromList([7]));
    });

    test('toBytesForSigning is independent of signature', () {
      final a = RouteResponse(
        requestId: 'id',
        responderPeerId: 'resp',
        targetPeerId: 'target',
        hopCount: 2,
        timestamp: 5,
        signature: Uint8List.fromList([1]),
      );
      final b = RouteResponse(
        requestId: 'id',
        responderPeerId: 'resp',
        targetPeerId: 'target',
        hopCount: 2,
        timestamp: 5,
        signature: Uint8List.fromList([9, 8]),
      );
      expect(a.toBytesForSigning(), b.toBytesForSigning());
    });
  });
}

