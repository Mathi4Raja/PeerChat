import 'dart:math';

class Route {
  final String destinationPeerId;
  final String nextHopPeerId;
  final int hopCount;
  final int lastUsedTimestamp;
  final int lastUpdatedTimestamp;
  final int successCount;
  final int failureCount;

  Route({
    required this.destinationPeerId,
    required this.nextHopPeerId,
    required this.hopCount,
    required this.lastUsedTimestamp,
    required this.lastUpdatedTimestamp,
    this.successCount = 0,
    this.failureCount = 0,
  });

  // Calculate route preference score
  double get preferenceScore {
    // Hop count penalty (exponential)
    final hopPenalty = pow(1.5, hopCount);
    
    // Success rate bonus
    final totalAttempts = successCount + failureCount;
    final successRate = totalAttempts > 0 ? successCount / totalAttempts : 0.5;
    
    // Recency bonus (routes used in last 5 minutes get bonus)
    final age = DateTime.now().millisecondsSinceEpoch - lastUsedTimestamp;
    final recencyBonus = age < 300000 ? 1.2 : 1.0;
    
    return (successRate * recencyBonus) / hopPenalty;
  }

  // Check if route is stale (not used in 30 minutes)
  bool get isStale {
    final age = DateTime.now().millisecondsSinceEpoch - lastUsedTimestamp;
    return age > 1800000; // 30 minutes in milliseconds
  }

  // Serialize for database storage
  Map<String, Object?> toMap() {
    return {
      'destination_peer_id': destinationPeerId,
      'next_hop_peer_id': nextHopPeerId,
      'hop_count': hopCount,
      'last_used_timestamp': lastUsedTimestamp,
      'last_updated_timestamp': lastUpdatedTimestamp,
      'success_count': successCount,
      'failure_count': failureCount,
    };
  }

  // Deserialize from database
  static Route fromMap(Map<String, Object?> map) {
    return Route(
      destinationPeerId: map['destination_peer_id'] as String,
      nextHopPeerId: map['next_hop_peer_id'] as String,
      hopCount: map['hop_count'] as int,
      lastUsedTimestamp: map['last_used_timestamp'] as int,
      lastUpdatedTimestamp: map['last_updated_timestamp'] as int,
      successCount: map['success_count'] as int? ?? 0,
      failureCount: map['failure_count'] as int? ?? 0,
    );
  }

  // Create a copy with updated fields
  Route copyWith({
    String? destinationPeerId,
    String? nextHopPeerId,
    int? hopCount,
    int? lastUsedTimestamp,
    int? lastUpdatedTimestamp,
    int? successCount,
    int? failureCount,
  }) {
    return Route(
      destinationPeerId: destinationPeerId ?? this.destinationPeerId,
      nextHopPeerId: nextHopPeerId ?? this.nextHopPeerId,
      hopCount: hopCount ?? this.hopCount,
      lastUsedTimestamp: lastUsedTimestamp ?? this.lastUsedTimestamp,
      lastUpdatedTimestamp: lastUpdatedTimestamp ?? this.lastUpdatedTimestamp,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
    );
  }
}
