import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/config/timer_config.dart';
import 'package:peerchat_secure/src/models/runtime_profile.dart';

void main() {
  group('TimerConfig emergencyBroadcast', () {
    test('returns timing for each runtime profile', () {
      final normal = TimerConfig.emergencyBroadcast(RuntimeProfile.normalDirect);
      final mesh = TimerConfig.emergencyBroadcast(RuntimeProfile.normalMesh);
      final battery =
          TimerConfig.emergencyBroadcast(RuntimeProfile.emergencyBattery);

      expect(normal.queueWindow, const Duration(seconds: 15));
      expect(mesh.retryInterval, const Duration(seconds: 3));
      expect(battery.queueWindow, const Duration(seconds: 15));
    });
  });

  group('DiscoveryTimerConfig', () {
    test('nextScanBase changes with profile and peer count', () {
      expect(
        DiscoveryTimerConfig.nextScanBase(
          runtimeProfile: RuntimeProfile.normalDirect,
          connectedPeerCount: 0,
          fileTransferActive: false,
        ),
        const Duration(seconds: 5),
      );
      expect(
        DiscoveryTimerConfig.nextScanBase(
          runtimeProfile: RuntimeProfile.normalDirect,
          connectedPeerCount: 3,
          fileTransferActive: false,
        ),
        const Duration(seconds: 30),
      );
      expect(
        DiscoveryTimerConfig.nextScanBase(
          runtimeProfile: RuntimeProfile.emergencyBattery,
          connectedPeerCount: 1,
          fileTransferActive: false,
        ),
        const Duration(seconds: 35),
      );
    });

    test('nextScanIntervalWithJitter stays within expected bounds', () {
      final random = Random(42);
      final out = DiscoveryTimerConfig.nextScanIntervalWithJitter(
        runtimeProfile: RuntimeProfile.normalDirect,
        connectedPeerCount: 1,
        fileTransferActive: false,
        batteryLow: true,
        random: random,
      );
      final baseDoubled = const Duration(seconds: 30);
      expect(out.inMilliseconds, greaterThanOrEqualTo(baseDoubled.inMilliseconds));
      expect(
        out.inMilliseconds,
        lessThanOrEqualTo(baseDoubled.inMilliseconds + DiscoveryTimerConfig.scanJitterMaxMs),
      );
    });

    test('activeScanDuration covers profile branches', () {
      expect(
        DiscoveryTimerConfig.activeScanDuration(
          runtimeProfile: RuntimeProfile.emergencyBattery,
          connectedPeerCount: 0,
          fileTransferActive: false,
          batteryLow: true,
        ),
        const Duration(seconds: 2),
      );
      expect(
        DiscoveryTimerConfig.activeScanDuration(
          runtimeProfile: RuntimeProfile.normalMesh,
          connectedPeerCount: 3,
          fileTransferActive: false,
          batteryLow: false,
        ),
        const Duration(seconds: 6),
      );
      expect(
        DiscoveryTimerConfig.activeScanDuration(
          runtimeProfile: RuntimeProfile.normalDirect,
          connectedPeerCount: 3,
          fileTransferActive: false,
          batteryLow: true,
        ),
        const Duration(seconds: 3),
      );
    });
  });
}

