import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;

enum NotificationTapTarget {
  chat,
  emergency,
}

class NotificationTapAction {
  final NotificationTapTarget target;
  final String? peerId;

  const NotificationTapAction({
    required this.target,
    this.peerId,
  });
}

class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  static const String _chatChannelId = 'chat_messages';
  static const String _chatChannelName = 'Chat messages';
  static const String _chatChannelDescription =
      'Incoming direct chat messages';
  static const String _broadcastChannelId = 'broadcast_mentions';
  static const String _broadcastChannelName = 'Broadcast mentions';
  static const String _broadcastChannelDescription =
      'Emergency broadcasts that mention you';

  final fln.FlutterLocalNotificationsPlugin _plugin =
      fln.FlutterLocalNotificationsPlugin();
  final StreamController<NotificationTapAction> _tapController =
      StreamController<NotificationTapAction>.broadcast();

  bool _initialized = false;
  Future<void>? _initFuture;
  NotificationTapAction? _pendingTapAction;
  String? _lastPayloadSignature;
  DateTime? _lastPayloadHandledAt;

  Stream<NotificationTapAction> get onTapAction => _tapController.stream;

  Future<void> init() async {
    if (_initialized) return;
    if (_initFuture != null) return _initFuture;
    _initFuture = _initInternal();
    await _initFuture;
  }

  Future<void> _initInternal() async {
    try {
      if (_initialized) return;

      const androidInit =
          fln.AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = fln.InitializationSettings(
        android: androidInit,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          _handlePayload(response.payload);
        },
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              fln.AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _handlePayload(launchDetails?.notificationResponse?.payload);
      }

      _initialized = true;
    } finally {
      _initFuture = null;
    }
  }

  NotificationTapAction? takePendingTapAction() {
    final value = _pendingTapAction;
    _pendingTapAction = null;
    return value;
  }

  Future<void> showChatMessage({
    required String peerId,
    required String senderLabel,
    required String content,
    required bool playSound,
  }) async {
    final me = const fln.Person(
      key: 'local_user',
      name: 'You',
    );
    final sender = fln.Person(
      key: peerId,
      name: senderLabel,
    );

    final details = fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _chatChannelId,
        _chatChannelName,
        channelDescription: _chatChannelDescription,
        importance: fln.Importance.high,
        priority: fln.Priority.high,
        category: fln.AndroidNotificationCategory.message,
        playSound: playSound,
        enableVibration: playSound,
        styleInformation: fln.MessagingStyleInformation(
          me,
          conversationTitle: senderLabel,
          groupConversation: false,
          messages: <fln.Message>[
            fln.Message(content, DateTime.now(), sender),
          ],
        ),
      ),
    );

    final payload = jsonEncode(<String, String>{
      'type': 'chat',
      'peer_id': peerId,
    });

    await _plugin.show(
      id: peerId.hashCode & 0x7fffffff,
      title: senderLabel,
      body: content,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> showBroadcastMention({
    required String messageId,
    required String senderLabel,
    required String content,
    required bool playSound,
  }) async {
    final fullBody = '$senderLabel: $content';
    final details = fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        _broadcastChannelId,
        _broadcastChannelName,
        channelDescription: _broadcastChannelDescription,
        importance: fln.Importance.high,
        priority: fln.Priority.high,
        category: fln.AndroidNotificationCategory.message,
        playSound: playSound,
        enableVibration: playSound,
        styleInformation: fln.BigTextStyleInformation(
          fullBody,
          contentTitle: 'Broadcast mention',
          summaryText: 'Emergency channel',
        ),
      ),
    );

    const payload = '{"type":"emergency"}';
    await _plugin.show(
      id: messageId.hashCode & 0x7fffffff,
      title: 'Broadcast mention',
      body: fullBody,
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> dispose() async {
    await _tapController.close();
  }

  void _handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final now = DateTime.now();
    if (_lastPayloadSignature == payload &&
        _lastPayloadHandledAt != null &&
        now.difference(_lastPayloadHandledAt!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _lastPayloadSignature = payload;
    _lastPayloadHandledAt = now;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'] as String?;
      NotificationTapAction? action;
      if (type == 'chat') {
        final peerId = decoded['peer_id'] as String?;
        if (peerId == null || peerId.isEmpty) return;
        action = NotificationTapAction(
          target: NotificationTapTarget.chat,
          peerId: peerId,
        );
      } else if (type == 'emergency') {
        action = const NotificationTapAction(
          target: NotificationTapTarget.emergency,
        );
      }

      if (action == null) return;
      _pendingTapAction = action;
      _tapController.add(action);
    } catch (_) {
      // Ignore malformed payload.
    }
  }
}
