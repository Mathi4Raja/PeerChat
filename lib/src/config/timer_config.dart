import '../models/runtime_profile.dart';
import 'dart:math';

/// Emergency send retry behavior by runtime profile.
class EmergencyBroadcastTiming {
  /// How long a not-yet-delivered emergency message stays retryable before
  /// the app marks delivery as failed.
  final Duration queueWindow;

  /// Delay between retry attempts while the message is in the queue window.
  final Duration retryInterval;

  const EmergencyBroadcastTiming({
    required this.queueWindow,
    required this.retryInterval,
  });
}

class TimerConfig {
  /// How long emergency broadcasts are retained in local storage before purge.
  ///
  /// Increase for longer local history; decrease to reduce DB growth.
  static const Duration emergencyRetentionWindow = Duration(hours: 24);

  static const EmergencyBroadcastTiming _normalDirectEmergencyTiming =
      EmergencyBroadcastTiming(
    queueWindow: Duration(seconds: 15),
    retryInterval: Duration(seconds: 3),
  );

  static const EmergencyBroadcastTiming _normalMeshEmergencyTiming =
      EmergencyBroadcastTiming(
    queueWindow: Duration(seconds: 15),
    retryInterval: Duration(seconds: 3),
  );

  static const EmergencyBroadcastTiming _batterySaverEmergencyTiming =
      EmergencyBroadcastTiming(
    queueWindow: Duration(seconds: 15),
    retryInterval: Duration(seconds: 3),
  );

  static EmergencyBroadcastTiming emergencyBroadcast(RuntimeProfile profile) {
    switch (profile) {
      case RuntimeProfile.normalDirect:
        return _normalDirectEmergencyTiming;
      case RuntimeProfile.normalMesh:
        return _normalMeshEmergencyTiming;
      case RuntimeProfile.emergencyBattery:
        return _batterySaverEmergencyTiming;
    }
  }
}

/// Bluetooth transport timers.
class BluetoothTimerConfig {
  /// Delay after Bluetooth turns on before starting dependent operations.
  static const Duration enableAfterTurnOnDelay = Duration(seconds: 2);

  /// Maximum time allowed for one Bluetooth connect attempt.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Wait time after disconnect before trying to reconnect.
  static const Duration reconnectAfterDisconnectDelay = Duration(seconds: 10);

  /// Background interval for reconnect checks when disconnected.
  static const Duration reconnectPollInterval = Duration(seconds: 30);
}

/// WiFi Direct transport timers.
class WiFiTimerConfig {
  /// Period for keep-alive heartbeats on active WiFi Direct links.
  static const Duration keepAliveInterval = Duration(seconds: 8);

  /// Max duration allowed for a WiFi Direct connection attempt.
  static const Duration connectionTimeout = Duration(seconds: 24);

  /// Cooldown after a failed/disconnected link before reconnect attempt.
  static const Duration reconnectCooldown = Duration(seconds: 5);

  /// Minimum spacing between repeated connection attempts to same peer.
  static const Duration connectionAttemptCooldown = Duration(seconds: 2);

  /// Timeout for entries in "pending connection attempt" state.
  static const Duration pendingAttemptTimeout = Duration(seconds: 12);

  /// Interval to scan/check whether reconnect should be attempted now.
  static const Duration reconnectCheckInterval = Duration(seconds: 8);

  /// If no reconnect failures for this long, reconnect-attempt counter resets.
  static const Duration reconnectAttemptResetThreshold = Duration(minutes: 5);

  /// Interval for transport health probes/maintenance checks.
  static const Duration healthCheckInterval = Duration(seconds: 10);

  /// Small delay before restarting WiFi Direct stack components.
  static const Duration restartDelay = Duration(milliseconds: 500);

  /// Minimum gap between discovery refresh operations.
  static const Duration discoveryRefreshCooldown = Duration(seconds: 12);

  /// Cooldown to avoid spamming repeated discovery failure notices.
  static const Duration discoveryFailureNoticeCooldown = Duration(seconds: 45);
}

/// Adaptive discovery scan timing.
class DiscoveryTimerConfig {
  /// Delay after enabling Bluetooth before starting discovery scans.
  static const Duration bluetoothEnableDelay = Duration(seconds: 2);

  /// Maximum random jitter added to scan interval to avoid synchronized scans.
  static const int scanJitterMaxMs = 3000;

  static Duration nextScanBase({
    required RuntimeProfile runtimeProfile,
    required int connectedPeerCount,
    required bool fileTransferActive,
  }) {
    switch (runtimeProfile) {
      case RuntimeProfile.normalMesh:
        if (connectedPeerCount <= 0) return const Duration(seconds: 5);
        if (connectedPeerCount <= 2) return const Duration(seconds: 7);
        return const Duration(seconds: 10);
      case RuntimeProfile.emergencyBattery:
        if (connectedPeerCount <= 0) return const Duration(seconds: 20);
        if (connectedPeerCount <= 2) return const Duration(seconds: 35);
        return const Duration(seconds: 60);
      case RuntimeProfile.normalDirect:
        if (fileTransferActive) return const Duration(seconds: 5);
        if (connectedPeerCount <= 0) return const Duration(seconds: 5);
        if (connectedPeerCount <= 2) return const Duration(seconds: 15);
        return const Duration(seconds: 30);
    }
  }

  static Duration nextScanIntervalWithJitter({
    required RuntimeProfile runtimeProfile,
    required int connectedPeerCount,
    required bool fileTransferActive,
    required bool batteryLow,
    required Random random,
  }) {
    var base = nextScanBase(
      runtimeProfile: runtimeProfile,
      connectedPeerCount: connectedPeerCount,
      fileTransferActive: fileTransferActive,
    );
    if (batteryLow && runtimeProfile != RuntimeProfile.emergencyBattery) {
      base = Duration(milliseconds: base.inMilliseconds * 2);
    }
    final jitterMs = random.nextInt(scanJitterMaxMs + 1);
    return Duration(milliseconds: base.inMilliseconds + jitterMs);
  }

  static Duration activeScanDuration({
    required RuntimeProfile runtimeProfile,
    required int connectedPeerCount,
    required bool fileTransferActive,
    required bool batteryLow,
  }) {
    if (runtimeProfile == RuntimeProfile.emergencyBattery) {
      return batteryLow
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3);
    }
    if (runtimeProfile == RuntimeProfile.normalMesh) {
      if (connectedPeerCount <= 0) return const Duration(seconds: 10);
      if (connectedPeerCount <= 2) return const Duration(seconds: 8);
      return const Duration(seconds: 6);
    }
    if (fileTransferActive) return const Duration(seconds: 10);
    if (connectedPeerCount <= 0) return const Duration(seconds: 8);
    if (connectedPeerCount <= 2) return const Duration(seconds: 6);
    return batteryLow ? const Duration(seconds: 3) : const Duration(seconds: 4);
  }
}

/// Mesh router background task timers.
class MeshRouterTimerConfig {
  /// Debounce window before queue-processing trigger is executed.
  static const Duration queueDebounce = Duration(seconds: 2);

  /// Periodic maintenance run interval for route/queue housekeeping.
  static const Duration maintenanceInterval = Duration(minutes: 5);

  /// Background interval for processing queued mesh work.
  static const Duration queueProcessInterval = Duration(seconds: 10);
}

/// Connection handshake/capability rebroadcast timers.
class ConnectionManagerTimerConfig {
  /// Delay before rebroadcasting capabilities after connection changes.
  static const Duration capabilityRebroadcastDelay =
      Duration(milliseconds: 700);
}

/// App-level polling and refresh timers.
class AppStateTimerConfig {
  /// Peer is treated as "active" if seen within this window.
  static const Duration activePeerWindow = Duration(minutes: 5);

  /// Grace period for initial discovery startup completion.
  static const Duration discoveryStartupTimeout = Duration(seconds: 2);

  /// Interval for refreshing peer list/state in app layer.
  static const Duration peerRefreshInterval = Duration(seconds: 10);

  /// Interval for battery status polling.
  static const Duration batteryPollInterval = Duration(minutes: 1);
}

/// File transfer maintenance timers.
class FileTransferTimerConfig {
  /// Transfer state older than this can be considered stale.
  static const Duration staleThreshold = Duration(minutes: 10);

  /// Max age for temporary transfer files before cleanup.
  static const Duration tempFileMaxAge = Duration(hours: 24);

  /// Interval for checking missing chunk ACKs and retry eligibility.
  static const Duration ackCheckInterval = Duration(seconds: 2);
}

/// Deduplication record cleanup timers.
class DeduplicationTimerConfig {
  /// Hard upper bound age for dedup records before forced cleanup.
  static const Duration absoluteMaxAge = Duration(days: 7);
}

/// Invalid-signature security timers.
class SecurityTimerConfig {
  /// Block duration applied after too many invalid signatures.
  static const Duration invalidSignatureBlockDuration = Duration(minutes: 10);

  /// Sliding window used to count invalid-signature events.
  static const Duration invalidSignatureDetectionWindow = Duration(minutes: 5);
}

/// Pending-ack cleanup timers.
class DeliveryAckTimerConfig {
  /// Max age for pending ACK entries before cleanup.
  static const Duration pendingAckMaxAge = Duration(days: 7);
}

/// Route lifecycle and discovery timeout timers.
class RouteTimerConfig {
  /// Route not refreshed within this age is treated as stale.
  static const Duration staleRouteAge = Duration(minutes: 30);

  /// Minimum base delay (seconds) for discovery retry backoff.
  static const int discoveryBackoffMinSeconds = 1;

  /// Maximum base delay (seconds) for discovery retry backoff.
  static const int discoveryBackoffMaxSeconds = 8;

  /// Caps exponential growth factor for discovery backoff.
  static const int discoveryBackoffMaxExponent = 3;
}

/// Emergency broadcast rate-limit window timer.
class EmergencyBroadcastPolicyConfig {
  /// Window duration used for per-sender emergency rate limiting.
  static const Duration senderRateLimitWindow = Duration(minutes: 1);
}

/// DB stale-data cleanup timers.
class DatabaseTimerConfig {
  /// Default max age for stored emergency broadcasts.
  static const Duration defaultBroadcastMaxAge =
      TimerConfig.emergencyRetentionWindow;

  /// Peer rows older than this (without refresh) are pruned.
  static const Duration stalePeerAge = Duration(minutes: 30);

  /// Route rows older than this are pruned.
  static const Duration staleRouteAge = Duration(minutes: 30);

  /// Endpoint rows older than this are pruned.
  static const Duration staleEndpointAge = Duration(hours: 2);
}

/// UI animation timers.
class UiTimerConfig {
  /// Bottom-nav item animation duration.
  static const Duration navItemAnimation = Duration(milliseconds: 200);

  /// Chat list auto-scroll animation duration.
  static const Duration chatAutoScrollAnimation = Duration(milliseconds: 300);

  /// Emergency screen auto-scroll animation duration.
  static const Duration emergencyAutoScrollAnimation =
      Duration(milliseconds: 250);
}
