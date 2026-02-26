/// App identity labels and ID display formatting constants.
class IdentityUiConfig {
  /// Fallback display name shown when user/peer name is unavailable.
  static const String defaultDisplayName = 'PeerChat User';

  /// Prefix used when generating the local device display name.
  static const String localDisplayNamePrefix = 'PeerChat';

  /// Label used for manually created peer entries.
  static const String manualAddedPeerLabel = 'Manually Added Peer';

  /// Minimum accepted length for manually pasted peer keys.
  static const int manualPeerKeyMinLength = 20;

  /// Common short ID length used in logs and human-readable IDs.
  static const int shortIdLength = 8;

  /// Number of ID chars appended in generated local device name.
  static const int localNameSuffixLength = 4;
}

/// Compact ID rendering constants used in debug/status screens.
class IdPreviewConfig {
  /// If ID length is less/equal, show full value without truncation.
  static const int fullDisplayThreshold = 12;

  /// Number of leading characters shown in shortened IDs.
  static const int leadingChars = 6;

  /// Number of trailing characters shown in debug shortened IDs.
  static const int debugTrailingChars = 6;

  /// Number of trailing characters shown in status list shortened IDs.
  static const int statusTrailingChars = 4;
}

/// Relative-time display constants.
class TimeFormatConfig {
  static const int secondMs = 1000;
  static const int minuteMs = 60 * secondMs;
  static const int hourMs = 60 * minuteMs;
  static const int dayMs = 24 * hourMs;
}
