import 'package:flutter/material.dart';

class ChatMessage {

  final String id;
  final String peerId; // Who we're chatting with
  final String content;
  final int timestamp;
  final bool isSentByMe;
  final MessageStatus status;
  final bool isRead;
  final int? hopCount;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToPeerId;

  ChatMessage({
    required this.id,
    required this.peerId,
    required this.content,
    required this.timestamp,
    required this.isSentByMe,
    required this.status,
    this.isRead = false,
    this.hopCount,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToPeerId,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'peerId': peerId,
        'content': content,
        'timestamp': timestamp,
        'isSentByMe': isSentByMe ? 1 : 0,
        'status': status.index,
        'isRead': isRead ? 1 : 0,
        'hopCount': hopCount,
        'replyToMessageId': replyToMessageId,
        'replyToContent': replyToContent,
        'replyToPeerId': replyToPeerId,
      };

  static ChatMessage fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as String,
        peerId: m['peerId'] as String,
        content: m['content'] as String,
        timestamp: m['timestamp'] as int,
        isSentByMe: (m['isSentByMe'] as int) == 1,
        status: MessageStatus.values[m['status'] as int],
        isRead:
            (m['isRead'] as int? ?? 1) == 1, // Default to read for old messages
        hopCount: _readHopCount(m['hopCount']),
        replyToMessageId: m['replyToMessageId'] as String?,
        replyToContent: m['replyToContent'] as String?,
        replyToPeerId: m['replyToPeerId'] as String?,
      );

  static int? _readHopCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

enum MessageStatus {
  sending,
  routing,
  sent,
  failed,
  queued,
}

extension MessageStatusUI on MessageStatus {
  IconData get icon {
    switch (this) {
      case MessageStatus.sending:
        return Icons.access_time_rounded;
      case MessageStatus.queued:
        return Icons.schedule_send_rounded;
      case MessageStatus.routing:
      case MessageStatus.sent:
        return Icons.alt_route_rounded;
      case MessageStatus.failed:
        return Icons.error_outline_rounded;
    }
  }

  Color get color {
    switch (this) {
      case MessageStatus.failed:
        return const Color(0xFFEF5350);
      default:
        return Colors.white.withValues(alpha: 0.55);
    }
  }
}



