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
  static const String _usernameKey = 'menu_username_v1';

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

  /// Returns stored custom username, or null if none set.
  Future<String?> loadUsername() async {
    final raw = await _storage.read(key: _usernameKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return raw.trim();
  }

  /// Stores a custom username. Pass null or empty to clear.
  Future<void> saveUsername(String? username) async {
    if (username == null || username.trim().isEmpty) {
      await _storage.delete(key: _usernameKey);
    } else {
      await _storage.write(key: _usernameKey, value: username.trim());
    }
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

  /// Optional callback called with the effective display name whenever
  /// the username is changed. AppState wires this to updateLocalName().
  final void Function(String displayName)? onDisplayNameChanged;

  bool _isInitialized = false;
  NotificationSettingsData _notifications =
      const NotificationSettingsData.defaults();
  String? _username;

  MenuSettingsController({
    MenuSettingsService? service,
    this.onDisplayNameChanged,
  }) : _service = service ?? MenuSettingsService();

  bool get isInitialized => _isInitialized;
  NotificationSettingsData get notifications => _notifications;

  /// Stored custom username. Null means "use generated name".
  String? get username => _username;

  Future<void> init() async {
    if (_isInitialized) return;
    _notifications = await _service.loadNotifications();
    _username = await _service.loadUsername();
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setNotifications(NotificationSettingsData value) async {
    _notifications = value;
    notifyListeners();
    await _service.saveNotifications(value);
  }

  /// Set (or clear) the custom username.
  /// [username] — pass null/empty to revert to generated name.
  /// [generatedFallback] — the key-derived name used when username is null.
  Future<void> setUsername(String? username, {required String generatedFallback}) async {
    final trimmed = username?.trim();
    _username = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    notifyListeners();
    await _service.saveUsername(_username);
    // Broadcast to mesh immediately
    final effective = _username ?? generatedFallback;
    onDisplayNameChanged?.call(effective);
  }
}
