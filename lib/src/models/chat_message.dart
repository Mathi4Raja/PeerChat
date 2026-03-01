class ChatMessage {
  final String id;
  final String peerId; // Who we're chatting with
  final String content;
  final int timestamp;
  final bool isSentByMe;
  final MessageStatus status;
  final bool isRead;
  final int? hopCount;

  ChatMessage({
    required this.id,
    required this.peerId,
    required this.content,
    required this.timestamp,
    required this.isSentByMe,
    required this.status,
    this.isRead = false,
    this.hopCount,
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
      };

  static ChatMessage fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as String,
        peerId: m['peerId'] as String,
        content: m['content'] as String,
        timestamp: m['timestamp'] as int,
        isSentByMe: (m['isSentByMe'] as int) == 1,
        status: MessageStatus.values[m['status'] as int],
        isRead: (m['isRead'] as int? ?? 1) == 1, // Default to read for old messages
        hopCount: _readHopCount(m['hopCount']),
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
  delivered,
  seen,
  failed,
  queued,
}
