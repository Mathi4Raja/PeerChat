import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/peer.dart';

void main() {
  test('Peer toMap/fromMap converts boolean flags through int storage', () {
    final peer = Peer(
      id: 'id',
      displayName: 'name',
      address: '127.0.0.1',
      lastSeen: 1,
      hasApp: true,
      isWiFi: true,
      isBluetooth: false,
    );
    final rebuilt = Peer.fromMap(peer.toMap());
    expect(rebuilt.id, peer.id);
    expect(rebuilt.displayName, peer.displayName);
    expect(rebuilt.address, peer.address);
    expect(rebuilt.lastSeen, peer.lastSeen);
    expect(rebuilt.hasApp, isTrue);
    expect(rebuilt.isWiFi, isTrue);
    expect(rebuilt.isBluetooth, isFalse);
  });
}

