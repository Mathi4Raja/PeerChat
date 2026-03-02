import 'dart:convert';

class ChatPayload {
  static const String _wireKind = 'pc_chat';
  static const int _wireVersion = 1;

  final String text;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToPeerId;

  const ChatPayload({
    required this.text,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToPeerId,
  });

  bool get hasReply =>
      (replyToMessageId != null && replyToMessageId!.isNotEmpty) ||
      (replyToContent != null && replyToContent!.isNotEmpty) ||
      (replyToPeerId != null && replyToPeerId!.isNotEmpty);

  String toWire() {
    if (!hasReply) return text;

    final reply = <String, Object?>{
      if (replyToMessageId != null && replyToMessageId!.isNotEmpty)
        'id': replyToMessageId,
      if (replyToContent != null && replyToContent!.isNotEmpty)
        't': replyToContent,
      if (replyToPeerId != null && replyToPeerId!.isNotEmpty)
        'p': replyToPeerId,
    };

    final payload = <String, Object?>{
      'k': _wireKind,
      'v': _wireVersion,
      't': text,
      if (reply.isNotEmpty) 'r': reply,
    };
    return jsonEncode(payload);
  }

  static ChatPayload decode(String wireContent) {
    try {
      final decoded = jsonDecode(wireContent);
      if (decoded is! Map) {
        return ChatPayload(text: wireContent);
      }
      final map = decoded.cast<String, dynamic>();
      if (map['k'] != _wireKind || map['v'] != _wireVersion) {
        return ChatPayload(text: wireContent);
      }

      final text = map['t'];
      if (text is! String) {
        return ChatPayload(text: wireContent);
      }

      String? replyToMessageId;
      String? replyToContent;
      String? replyToPeerId;
      final reply = map['r'];
      if (reply is Map) {
        replyToMessageId = _readNonEmptyString(reply['id']);
        replyToContent = _readNonEmptyString(reply['t']);
        replyToPeerId = _readNonEmptyString(reply['p']);
      }

      return ChatPayload(
        text: text,
        replyToMessageId: replyToMessageId,
        replyToContent: replyToContent,
        replyToPeerId: replyToPeerId,
      );
    } catch (_) {
      return ChatPayload(text: wireContent);
    }
  }

  static String? _readNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  }
}
