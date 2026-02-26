/// Shared wire-protocol markers and packet layout constants.
class ProtocolConfig {
  /// Keepalive frame payload used by transports and router.
  static const List<int> keepAlivePacket = [0xFF, 0xFF];

  /// Expected keepalive payload length.
  static const int keepAlivePacketLength = 2;

  /// Keepalive byte value repeated in payload.
  static const int keepAliveByte = 0xFF;
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

/// File-transfer protocol message and storage naming constants.
class FileTransferProtocolConfig {
  /// Offset of marker byte in raw transfer frame.
  static const int markerOffset = 0;

  /// Offset of message type byte in raw transfer frame.
  static const int typeOffset = 1;

  /// Bytes before file-id field: marker (1) + type (1).
  static const int prefixHeaderBytes = 2;

  /// Reason payload sent when receiver storage is insufficient.
  static const String insufficientStorageReason = 'INSUFFICIENT_STORAGE';

  /// Reason payload sent when incoming file is too large.
  static const String fileTooLargeReason = 'FILE_TOO_LARGE';
}

/// File-transfer artifact path naming constants.
class FileTransferPathConfig {
  /// Prefix of temporary per-transfer directory.
  static const String transferTempPrefix = 'peerchat_transfer_';

  /// App-storage fallback folder for received files.
  static const String fallbackReceivedFolderName = 'peerchat_files';

  /// Shared root folder name on Android external storage.
  static const String androidSharedFolderName = 'PeerChat';

  /// Prefix for fallback received filenames when source name is invalid.
  static const String defaultReceivedPrefix = 'received_';

  /// Chunk part filename prefix in temp transfer directory.
  static const String chunkPartPrefix = 'chunk_';

  /// Chunk part filename extension.
  static const String chunkPartExtension = '.part';
}
