import 'package:flutter/foundation.dart';

class Peer {
  final String id; // fingerprint or public key base64
  final String displayName;
  final String address; // ip:port or MAC address
  final int lastSeen;
  final bool hasApp; // true if discovered via mDNS (has PeerChat app)

  Peer({
    required this.id,
    required this.displayName,
    required this.address,
    required this.lastSeen,
    this.hasApp = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'displayName': displayName,
        'address': address,
        'lastSeen': lastSeen,
        'hasApp': hasApp ? 1 : 0,
      };

  static Peer fromMap(Map<String, Object?> m) => Peer(
        id: m['id'] as String,
        displayName: m['displayName'] as String,
        address: m['address'] as String,
        lastSeen: m['lastSeen'] as int,
        hasApp: (m['hasApp'] as int?) == 1,
      );
}
