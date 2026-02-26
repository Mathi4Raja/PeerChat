/// Message payload, TTL, and wire-ID limits.
class MessageLimits {
  /// Expected canonical ID length used on the wire (UUID-style).
  static const int wireIdLength = 36;

  /// Sender prefix length used when constructing generated IDs.
  static const int generatedIdSenderPrefixLength = 8;

  /// UUID fragment length used in generated IDs.
  static const int generatedIdUuidFragmentLength = 27;

  /// Maximum serialized message content size accepted/sent (bytes).
  static const int maxContentBytes = 65536; // 64 KiB

  /// Lower bound for standard message TTL hops.
  static const int ttlMin = 8;

  /// Upper bound for standard message TTL hops.
  static const int ttlMax = 16;

  /// TTL used for route-control/system routing messages.
  static const int routeControlTtl = 8;

  /// TTL used for read-receipt propagation.
  static const int readReceiptTtl = 12;

  /// TTL used for ACK propagation.
  static const int acknowledgmentTtl = 8;

  /// Future timestamp tolerance before treating message clock as invalid.
  static const int futureClockSkewToleranceMs = 300000; // 5 min

  /// Default expiry duration for messages when explicit expiry is absent.
  static const int defaultExpiryDurationMs = 604800000; // 7 days
}

/// Emergency broadcast storage, fanout, and rate limits.
class BroadcastLimits {
  /// Max emergency messages accepted per sender per minute.
  static const int maxPerMinute = 3;

  /// Hard global cap for persisted emergency messages.
  static const int maxGlobalRows = 700;

  /// Hard cap for persisted emergency messages from one sender.
  static const int maxRowsPerSender = 100;

  /// Broadcast TTL hops for emergency messages.
  static const int messageTtl = 5;

  /// Minimum relay fanout target.
  static const int fanoutMin = 2;

  /// Maximum relay fanout target.
  static const int fanoutMax = 3;

  /// Hop count where probabilistic decay begins.
  static const int probabilisticDecayHopThreshold = 2;

  /// Drop probability after decay threshold (0.0-1.0).
  static const double probabilisticDecayDropChance = 0.5;

  /// Default DB query/page size when loading emergency history.
  static const int defaultQueryLimit = 200;

  /// Max messages rendered in emergency screen history at once.
  static const int screenHistoryLimit = 300;
}

/// Outbound queue sizing and retry caps.
class QueueLimits {
  /// Global max pending outbound queue size across peers.
  static const int maxQueueSize = 5000;

  /// Max queued outbound messages per peer.
  static const int maxMessagesPerPeer = 50;

  /// Max retry attempts before dropping one queued message.
  static const int maxRetries = 50;

  /// Base retry interval used before backoff scaling.
  static const int baseRetryIntervalMs = 30000;

  /// Cap on exponential backoff power to avoid unbounded delays.
  static const int backoffExponentCap = 10;
}

/// File transfer protocol and resource limits.
class FileTransferLimits {
  /// Max file size user is allowed to send (bytes).
  static const int maxSendFileSizeBytes = 1024 * 1024 * 1024; // 1 GiB

  /// File chunk payload size (bytes) used on wire.
  static const int chunkSizeBytes = 65536; // 64 KiB

  /// Max chunks that can be in-flight before ACKs arrive.
  static const int maxInFlightChunks = 5;

  /// Max retries per chunk before transfer failure.
  static const int maxChunkRetries = 5;

  /// Persist transfer state after every N chunks for crash recovery.
  static const int statePersistEveryNChunks = 10;

  /// Required free-space multiplier over file size (safety headroom).
  static const double minStorageHeadroomMultiplier = 1.2;

  /// Protocol marker byte used to identify file-transfer frames.
  static const int protocolMarker = 0xFE;

  /// Expected on-wire file ID length.
  static const int wireFileIdLength = 36;

  /// Fixed chunk header size (bytes) in framed payload.
  static const int chunkHeaderBytes = 4;

  /// ACK wait timeout for WiFi transport.
  static const int ackTimeoutWifiMs = 10000;

  /// ACK wait timeout for Bluetooth transport.
  static const int ackTimeoutBluetoothMs = 15000;

  /// Fallback storage estimate when platform API cannot provide free space.
  static const int fallbackAvailableStorageBytes = 1024 * 1024 * 1024; // 1 GiB

  /// Multiplier to convert df "blocks" to bytes on supported systems.
  static const int dfBlocksToBytesMultiplier = 1024;
}

/// Routing protocol and pruning limits.
class RouteLimits {
  /// Expected request ID length for route control packets.
  static const int requestIdWireLength = 36;

  /// Minimum samples required before considering failure-based pruning.
  static const int failurePruneMinSamples = 5;

  /// Failure ratio threshold above which route is pruned.
  static const double failurePruneThreshold = 0.7;

  /// Base hop penalty factor in route score calculation.
  static const double hopPenaltyBase = 1.5;

  /// Recency bonus applies if route update is within this window.
  static const int recencyBonusWindowMs = 300000; // 5 min

  /// Multiplier applied when recency bonus is active.
  static const double recencyBonusMultiplier = 1.2;

  /// Absolute stale age for route rows before cleanup.
  static const int staleAgeMs = 1800000; // 30 min
}

/// Opportunistic mesh relay fanout caps.
class MeshForwardingLimits {
  /// Hard cap on opportunistic forward count.
  static const int opportunisticMaxForwardCount = 3;

  /// Min fanout for opportunistic forwarding.
  static const int opportunisticFanoutMin = 2;

  /// Max fanout for opportunistic forwarding.
  static const int opportunisticFanoutMax = 3;
}

/// Deduplication cache sizing limits.
class DeduplicationLimits {
  /// Max dedup cache entries retained in memory/storage.
  static const int maxCacheSize = 10000;

  /// Max message fingerprints tracked for duplicate detection.
  static const int maxFingerprints = 5000;

  /// Max forwarded-to peer-entry set size tracked per message.
  static const int maxForwardedToEntries = 2000;

  /// Fractional divisor used to compute eviction batch size.
  static const int evictionDivisor = 10;

  /// Fractional divisor used to compute trim target size.
  static const int trimDivisor = 2;
}

/// Security threshold limits.
class SecurityLimits {
  /// Invalid signature count threshold before temporary block is applied.
  static const int maxInvalidSignatures = 3;
}

/// Connection validation limits.
class ConnectionLimits {
  /// Max handshake age tolerated during connection validation.
  static const int handshakeMaxAgeMs = 300000; // 5 min
}

/// UI display hard caps.
class UiLimits {
  /// Badge count display cap; values above this should render as "99+".
  static const int badgeDisplayCap = 99;

  /// Online participant count display cap for channel headers.
  /// Values above this should render as "9999+".
  static const int onlineCountDisplayCap = 9999;
}
