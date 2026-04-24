import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/protocol_config.dart';

/// Service for interacting with device hardware and system-level settings.
class DeviceSystemService {
  static const MethodChannel _channel =
      MethodChannel('peerchat_secure/device_status');
  static const EventChannel _btEventChannel =
      EventChannel('peerchat_secure/bluetooth_state');

  /// Returns battery level percentage and charging state.
  ///
  /// Non-Android platforms return a safe fallback.
  Future<BatteryStatus> getStatus() async {
    if (!Platform.isAndroid) {
      return const BatteryStatus(level: 100, isCharging: false);
    }

    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>('getBatteryStatus');
      final level = (result?['level'] as int?) ?? 100;
      final isCharging = (result?['isCharging'] as bool?) ?? false;
      return BatteryStatus(level: level.clamp(0, 100), isCharging: isCharging);
    } catch (_) {
      return const BatteryStatus(level: 100, isCharging: false);
    }
  }

  /// Opens Android location settings so users can enable location quickly.
  /// Falls back to app settings when system settings cannot be opened.
  Future<bool> openLocationSettings() async {
    if (!Platform.isAndroid) {
      return openAppSettings();
    }

    try {
      final opened = await _channel.invokeMethod<bool>('openLocationSettings');
      if (opened == true) {
        return true;
      }
    } catch (_) {
      // Fall through to app settings fallback.
    }

    return openAppSettings();
  }

  /// Checks if the "Modify System Settings" permission is granted.
  Future<bool> checkSystemSettingsPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('checkSystemSettingsPermission') ?? false;
  }

  /// Opens the system settings permission page for this app.
  Future<bool> openSystemSettingsPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('openSystemSettingsPermission') ?? false;
  }

  /// Toggles Bluetooth state (Android only).
  Future<bool> toggleBluetooth(bool enable) async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('toggleBluetooth', {'enable': enable}) ?? false;
    } catch (e) {
      debugPrint('Error toggling bluetooth: $e');
      return false;
    }
  }

  /// Returns whether Bluetooth is currently enabled.
  Future<bool> isBluetoothEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isBluetoothEnabled') ?? false;
    } catch (e) {
      debugPrint('Error reading bluetooth state: $e');
      return false;
    }
  }

  /// Returns whether Wi-Fi Hotspot is currently enabled.
  /// Returns null when Android blocks hotspot state detection.
  Future<bool?> isHotspotEnabled() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('isHotspotEnabled');
    } catch (e) {
      debugPrint('Error reading hotspot state: $e');
      return null;
    }
  }

  /// A stream of the current Bluetooth state (enabled/disabled).
  Stream<bool> get onBluetoothStateChanged {
    if (!Platform.isAndroid) return const Stream.empty();
    return _btEventChannel.receiveBroadcastStream().map((event) => event as bool);
  }

  /// Fetches a list of installed apps that can be shared.
  Future<List<Map<String, dynamic>>> getInstalledApps() async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? apps = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');
      if (apps == null) return [];
      return apps.map((a) => Map<String, dynamic>.from(a as Map)).toList();
    } catch (e) {
      debugPrint('Error getting installed apps: $e');
      return [];
    }
  }

  /// Fetches the raw icon bytes for a package.
  Future<Uint8List?> getAppIcon(String packageName) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('getAppIcon', {'packageName': packageName});
    } catch (e) {
      debugPrint('Error fetching icon for $packageName: $e');
      return null;
    }
  }

  /// Checks if "All Files Access" (MANAGE_EXTERNAL_STORAGE) is granted on Android 11+.
  Future<bool> checkAllFilesPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('checkAllFilesPermission') ?? true;
  }

  /// Opens the system settings to grant "All Files Access".
  Future<bool> openAllFilesPermission() async {
    if (!Platform.isAndroid) return true;
    return await _channel.invokeMethod<bool>('openAllFilesPermission') ?? false;
  }

  /// Fetches media assets (images or videos) using Native MediaStore.
  Future<List<MediaAsset>> getMediaAssets(String type) async {
    if (!Platform.isAndroid) return [];
    try {
      final List<dynamic>? assets = await _channel.invokeMethod<List<dynamic>>(
        'getMediaAssets',
        {'type': type},
      );
      if (assets == null) return [];
      return assets.map((a) => MediaAsset.fromMap(Map<String, dynamic>.from(a as Map))).toList();
    } catch (e) {
      debugPrint('Error getting media assets ($type): $e');
      return [];
    }
  }

  /// Opens Android Hotspot/Tethering settings.
  Future<bool> openHotspotSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('openHotspotSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android Bluetooth settings.
  Future<bool> openBluetoothSettings() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('openBluetoothSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class MediaAsset {
  final String name;
  final String path;
  final int size;
  final String mimeType;

  MediaAsset({
    required this.name,
    required this.path,
    required this.size,
    required this.mimeType,
  });

  factory MediaAsset.fromMap(Map<String, dynamic> map) {
    return MediaAsset(
      name: map['name'] ?? 'Unknown',
      path: map['path'] ?? '',
      size: map['size'] ?? 0,
      mimeType: map['mimeType'] ?? '',
    );
  }
}

class BatteryStatus {
  final int level;
  final bool isCharging;

  const BatteryStatus({
    required this.level,
    required this.isCharging,
  });

  bool get isLow =>
      !isCharging && level <= BatteryPolicyConfig.lowBatteryThresholdPercent;
}
