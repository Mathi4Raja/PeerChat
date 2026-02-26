import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/protocol_config.dart';

/// Lightweight battery status fetcher without external dependencies.
class BatteryStatusService {
  static const MethodChannel _channel =
      MethodChannel('peerchat_secure/device_status');

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
