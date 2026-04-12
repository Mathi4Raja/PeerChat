import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class NotificationSoundService {
  static final NotificationSoundService _instance =
      NotificationSoundService._internal();
  factory NotificationSoundService() => _instance;
  NotificationSoundService._internal();

  int _lastIncomingPlayMs = 0;
  int _lastSentPlayMs = 0;
  int _lastBroadcastPlayMs = 0;
  int _lastBroadcastIncomingPlayMs = 0;
  static const int _incomingMinGapMs = 900;
  static const int _sentMinGapMs = 180;
  static const int _broadcastMinGapMs = 300;
  static const int _broadcastIncomingMinGapMs = 500;

  Future<void> playIncoming() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastIncomingPlayMs < _incomingMinGapMs) return;
    _lastIncomingPlayMs = now;

    try {
      await FlutterRingtonePlayer().playNotification();
    } catch (e) {
      debugPrint('Notification sound failed: $e');
    }
  }

  Future<void> playSentTick() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSentPlayMs < _sentMinGapMs) return;
    _lastSentPlayMs = now;

    try {
      await FlutterRingtonePlayer().play(
        fromAsset: 'assets/sounds/send_tick.wav',
        volume: 0.9,
        looping: false,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint('Sent tick asset failed, falling back: $e');
      try {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.notification,
          ios: IosSounds.sentMessage,
          volume: 0.65,
          looping: false,
          asAlarm: false,
        );
      } catch (fallbackError) {
        debugPrint('Sent tick fallback failed: $fallbackError');
      }
    }
  }

  Future<void> playBroadcastIncomingAlert() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBroadcastIncomingPlayMs < _broadcastIncomingMinGapMs) {
      return;
    }
    _lastBroadcastIncomingPlayMs = now;

    try {
      await _playBroadcastAlert(
        volume: 0.6,
      );
    } catch (e) {
      debugPrint('Broadcast incoming alert asset failed, falling back: $e');
      try {
        await FlutterRingtonePlayer().playNotification(
          volume: 0.55,
          looping: false,
          asAlarm: false,
        );
      } catch (fallbackError) {
        debugPrint('Broadcast incoming alert fallback failed: $fallbackError');
      }
    }
  }

  Future<void> playBroadcastSentAlert() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBroadcastPlayMs < _broadcastMinGapMs) return;
    _lastBroadcastPlayMs = now;

    try {
      await _playBroadcastAlert(
        volume: 0.9,
      );
    } catch (e) {
      debugPrint('Broadcast sent alert asset failed, falling back: $e');
      try {
        await FlutterRingtonePlayer().play(
          android: AndroidSounds.alarm,
          ios: IosSounds.alarm,
          volume: 0.8,
          looping: false,
          asAlarm: false,
        );
      } catch (fallbackError) {
        debugPrint('Broadcast sent alert fallback failed: $fallbackError');
      }
    }
  }

  Future<void> _playBroadcastAlert({
    required double volume,
  }) async {
    await FlutterRingtonePlayer().play(
      fromAsset: 'assets/sounds/broadcast_alert.wav',
      volume: volume,
      looping: false,
      asAlarm: false,
    );
  }

  Future<void> dispose() async {
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {
      // Ignore stop failures.
    }
  }
}
