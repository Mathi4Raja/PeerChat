/// Communication mode determines how a message is delivered.
///
/// - [direct]: Peer is directly connected. Encrypt → sign → send immediately.
///   Bypasses queue and route lookup entirely.
/// - [mesh]: Peer is NOT directly connected. Use route-based forwarding
///   with queue fallback (delay-tolerant networking).
/// - [emergencyBroadcast]: Public broadcast to all nearby peers.
///   Signed but NOT encrypted. Low TTL. Rate-limited.
enum CommunicationMode {
  direct,
  mesh,
  emergencyBroadcast,
}

/// Broadcast destination sentinel value.
const String broadcastEmergencyDestination = 'BROADCAST_EMERGENCY';

/// Determines the correct communication mode for a given destination.
CommunicationMode selectMode({
  required String destinationId,
  required List<String> connectedPeerIds,
}) {
  if (destinationId == broadcastEmergencyDestination) {
    return CommunicationMode.emergencyBroadcast;
  } else if (connectedPeerIds.contains(destinationId)) {
    return CommunicationMode.direct;
  } else {
    return CommunicationMode.mesh;
  }
}
