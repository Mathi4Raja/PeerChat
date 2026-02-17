class ChatMessage {
  final String id;
  final String peerId; // Who we're chatting with
  final String content;
  final int timestamp;
  final bool isSentByMe;
  final MessageStatus status;

  ChatMessage({
    required this.id,
    required this.peerId,
    required this.content,
    required this.timestamp,
    required this.isSentByMe,
    required this.status,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'peerId': peerId,
        'content': content,
        'timestamp': timestamp,
        'isSentByMe': isSentByMe ? 1 : 0,
        'status': status.index,
      };

  static ChatMessage fromMap(Map<String, Object?> m) => ChatMessage(
        id: m['id'] as String,
        peerId: m['peerId'] as String,
        content: m['content'] as String,
        timestamp: m['timestamp'] as int,
        isSentByMe: (m['isSentByMe'] as int) == 1,
        status: MessageStatus.values[m['status'] as int],
      );
}

enum MessageStatus {
  sending,
  sent,
  delivered,
  failed,
}
