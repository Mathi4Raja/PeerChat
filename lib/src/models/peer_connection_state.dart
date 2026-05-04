enum PeerConnectionState {
  disconnected,
  connecting,
  handshakePending,
  connected,
  disconnecting,
}

extension PeerConnectionStateStorage on PeerConnectionState {
  String get storageValue {
    return switch (this) {
      PeerConnectionState.disconnected => 'disconnected',
      PeerConnectionState.connecting => 'connecting',
      PeerConnectionState.handshakePending => 'handshake_pending',
      PeerConnectionState.connected => 'connected',
      PeerConnectionState.disconnecting => 'disconnecting',
    };
  }
}
