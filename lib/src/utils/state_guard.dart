import '../models/chat_message.dart';
import '../models/peer_connection_state.dart';
import '../services/event_sourcing_logger.dart';

class InvalidStateTransitionException implements Exception {
  final String message;
  final String entityId;
  final String fromState;
  final String toState;

  InvalidStateTransitionException(
      this.entityId, this.fromState, this.toState)
      : message = 'Invalid transition for $entityId: $fromState -> $toState';

  @override
  String toString() => message;
}

class StateGuard {
  static final Map<MessageStatus, Set<MessageStatus>> _messageTransitions = {
    MessageStatus.sending: {MessageStatus.queued, MessageStatus.routing, MessageStatus.failed},
    MessageStatus.queued: {MessageStatus.routing, MessageStatus.failed},
    MessageStatus.routing: {MessageStatus.sent, MessageStatus.failed},
    MessageStatus.sent: {MessageStatus.failed}, // Sometimes network failure post-send
    MessageStatus.failed: {MessageStatus.queued, MessageStatus.sending}, // Retries
  };

  static final Map<PeerConnectionState, Set<PeerConnectionState>> _connectionTransitions = {
    PeerConnectionState.disconnected: {PeerConnectionState.connecting},
    PeerConnectionState.connecting: {PeerConnectionState.handshake_pending, PeerConnectionState.disconnected},
    PeerConnectionState.handshake_pending: {PeerConnectionState.connected, PeerConnectionState.disconnected},
    PeerConnectionState.connected: {PeerConnectionState.disconnecting, PeerConnectionState.disconnected},
    PeerConnectionState.disconnecting: {PeerConnectionState.disconnected},
  };

  static void transitionMessage(String messageId, MessageStatus current, MessageStatus next, {String? correlationId}) {
    final allowed = _messageTransitions[current] ?? {};
    if (!allowed.contains(next) && current != next) {
      final e = InvalidStateTransitionException(messageId, current.name, next.name);
      EventSourcingLogger().logEvent(
        entityId: messageId,
        eventType: 'MESSAGE_TRANSITION_ERROR',
        payload: {
          'from': current.name,
          'to': next.name,
          'error': e.toString(),
        },
        correlationId: correlationId,
      );
      throw e;
    }

    EventSourcingLogger().logEvent(
      entityId: messageId,
      eventType: 'MESSAGE_STATE_TRANSITION',
      payload: {
        'from': current.name,
        'to': next.name,
      },
      correlationId: correlationId,
    );
  }

  static void transitionConnection(String transportId, PeerConnectionState current, PeerConnectionState next, {String? correlationId}) {
    final allowed = _connectionTransitions[current] ?? {};
    if (!allowed.contains(next) && current != next) {
      final e = InvalidStateTransitionException(transportId, current.name, next.name);
      EventSourcingLogger().logEvent(
        entityId: transportId,
        eventType: 'CONNECTION_TRANSITION_ERROR',
        payload: {
          'from': current.name,
          'to': next.name,
          'error': e.toString(),
        },
        correlationId: correlationId,
      );
      throw e;
    }

    EventSourcingLogger().logEvent(
      entityId: transportId,
      eventType: 'CONNECTION_STATE_TRANSITION',
      payload: {
        'from': current.name,
        'to': next.name,
      },
      correlationId: correlationId,
    );
  }
}
