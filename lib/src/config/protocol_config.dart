/// Shared wire-protocol markers and packet layout constants.
class ProtocolConfig {
  /// Keepalive frame payload used by transports and router.
  static const List<int> keepAlivePacket = [0xFF, 0xFF];

  /// Expected keepalive payload length.
  static const int keepAlivePacketLength = 2;

  /// Keepalive byte value repeated in payload.
  static const int keepAliveByte = 0xFF;
}

/// Token bucket rate limits for flow control.
class RateLimitConfig {
  /// Maximum number of messages a peer can burst before being dropped.
  static const double tokenBucketCapacity = 50.0;

  /// Number of messages a peer can send per second continuously.
  static const double tokenBucketRefillRate = 10.0;
}

/// Queue behavior constants not tied to retry backoff math.
class QueuePolicyConfig {
  /// Age threshold after which queued messages get a temporary priority boost.
  static const int stalePriorityBoostAgeMs = 60 * 60 * 1000; // 1 hour
}

/// Battery-state policy constants.
class BatteryPolicyConfig {
  /// Battery percent at/below which device is treated as low battery.
  static const int lowBatteryThresholdPercent = 20;
}

/// WiFi discovery failure parsing tokens.
class WiFiDiscoveryErrorConfig {
  /// Tokens indicating missing location permission.
  static const List<String> missingPermissionTokens = [
    'MISSING_PERMISSION_ACCESS_COARSE_LOCATION',
    'ACCESS_COARSE_LOCATION',
    'ACCESS_FINE_LOCATION',
    'MISSING_PERMISSION',
  ];

  /// Error code emitted on some devices for missing permission.
  static const String missingPermissionCode = '8034';

  /// Tokens indicating location service/settings are disabled.
  static const List<String> locationDisabledTokens = [
    'LOCATION_SETTINGS',
    'LOCATION IS TURNED OFF',
    'LOCATION_DISABLED',
  ];
}

/// Keyword-based transport/discovery device filtering.
class DeviceHeuristicConfig {
  /// Bonded-device names to skip for active Bluetooth peer connect attempts.
  static const List<String> bondedSkipKeywords = [
    'buds',
    'fitpro',
    'watch',
    'tiger',
    'kraken',
    'st-',
    'pc',
    'laptop',
  ];

  /// Bonded-device name hints treated as phone-like peers.
  static const List<String> bondedPhoneHints = [
    'nokia',
    'samsung',
    'infinix',
    'xiaomi',
    'oppo',
    'vivo',
    'realme',
    'oneplus',
    'pixel',
    'iphone',
    'android',
    'phone',
  ];

  /// Bluetooth discovery names indicating audio accessories (non-mesh).
  static const List<String> nonMeshAudioKeywords = [
    'headphone',
    'earbuds',
    'airpods',
    'buds',
    'speaker',
    'soundbar',
    'audio',
    'beats',
    'bose',
    'sony wh',
    'jbl',
  ];

  /// Bluetooth discovery names indicating wearables (non-mesh).
  static const List<String> nonMeshWearableKeywords = [
    'watch',
    'band',
    'fit',
    'tracker',
  ];

  /// Bluetooth discovery names indicating vehicle systems (non-mesh).
  static const List<String> nonMeshVehicleKeywords = [
    'car',
    'auto',
    'vehicle',
  ];

  /// Bluetooth discovery names indicating peripherals/IoT (non-mesh).
  static const List<String> nonMeshPeripheralKeywords = [
    'tv',
    'remote',
    'controller',
    'gamepad',
    'keyboard',
    'mouse',
  ];
}

