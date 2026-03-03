/// Communication mode determines how a message is delivered.
///
/// - [mesh]: Use route-based forwarding
///   with queue fallback (delay-tolerant networking).
/// - [emergencyBroadcast]: Public broadcast to all nearby peers.
///   Signed but NOT encrypted. Low TTL. Rate-limited.
enum CommunicationMode {
  mesh,
  emergencyBroadcast,
}

/// Broadcast destination sentinel value.
const String broadcastEmergencyDestination = 'BROADCAST_EMERGENCY';

/// Determines the correct communication mode for a given destination.
CommunicationMode selectMode({
  required String destinationId,
}) {
  if (destinationId == broadcastEmergencyDestination) {
    return CommunicationMode.emergencyBroadcast;
  }
  // Messages now always flow through the mesh pipeline.
  return CommunicationMode.mesh;
}
