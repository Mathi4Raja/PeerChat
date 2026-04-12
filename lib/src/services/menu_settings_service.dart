import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class NotificationSettingsData {
  final bool sound;
  final bool chatMessages;
  final bool broadcastChannel;

  const NotificationSettingsData({
    required this.sound,
    required this.chatMessages,
    required this.broadcastChannel,
  });

  const NotificationSettingsData.defaults()
      : sound = true,
        chatMessages = true,
        broadcastChannel = true;

  NotificationSettingsData copyWith({
    bool? sound,
    bool? chatMessages,
    bool? broadcastChannel,
  }) {
    return NotificationSettingsData(
      sound: sound ?? this.sound,
      chatMessages: chatMessages ?? this.chatMessages,
      broadcastChannel: broadcastChannel ?? this.broadcastChannel,
    );
  }
}

class MenuSettingsService {
  static const String _notifSoundKey = 'menu_notifications_sound_v1';
  static const String _notifMessagesKey = 'menu_notifications_messages_v1';
  static const String _notifBroadcastKey = 'menu_notifications_broadcast_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<NotificationSettingsData> loadNotifications() async {
    final sound = await _readBool(_notifSoundKey, true);
    final messages = await _readBool(_notifMessagesKey, true);
    final broadcast = await _readBool(_notifBroadcastKey, true);
    return NotificationSettingsData(
      sound: sound,
      chatMessages: messages,
      broadcastChannel: broadcast,
    );
  }

  Future<void> saveNotifications(NotificationSettingsData notifications) async {
    await _writeBool(_notifSoundKey, notifications.sound);
    await _writeBool(_notifMessagesKey, notifications.chatMessages);
    await _writeBool(_notifBroadcastKey, notifications.broadcastChannel);
  }

  Future<bool> _readBool(String key, bool fallback) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return fallback;
    return raw == 'true';
  }

  Future<void> _writeBool(String key, bool value) async {
    await _storage.write(key: key, value: value ? 'true' : 'false');
  }
}

class MenuSettingsController extends ChangeNotifier {
  final MenuSettingsService _service;

  bool _isInitialized = false;
  NotificationSettingsData _notifications =
      const NotificationSettingsData.defaults();

  MenuSettingsController({MenuSettingsService? service})
      : _service = service ?? MenuSettingsService();

  bool get isInitialized => _isInitialized;
  NotificationSettingsData get notifications => _notifications;

  Future<void> init() async {
    if (_isInitialized) return;
    _notifications = await _service.loadNotifications();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setNotifications(NotificationSettingsData value) async {
    _notifications = value;
    notifyListeners();
    await _service.saveNotifications(value);
  }
}
