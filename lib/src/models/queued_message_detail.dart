import 'queued_message.dart';
import 'mesh_message.dart';

class QueuedMessageDetail {
  final String messageId;
  final String recipientPeerId;
  final String nextHopPeerId;
  final MessagePriority priority;
  final int queuedTimestamp;
  final int attemptCount;
  final QueueOrigin origin;
  final String? contentPreview;

  QueuedMessageDetail({
    required this.messageId,
    required this.recipientPeerId,
    required this.nextHopPeerId,
    required this.priority,
    required this.queuedTimestamp,
    required this.attemptCount,
    required this.origin,
    this.contentPreview,
  });
}
