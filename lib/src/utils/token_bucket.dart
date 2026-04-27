class TokenBucket {
  final double capacity;
  final double refillRatePerSecond;
  
  double _tokens;
  int _lastRefillTimestamp;

  TokenBucket({
    required this.capacity,
    required this.refillRatePerSecond,
  })  : _tokens = capacity,
        _lastRefillTimestamp = DateTime.now().millisecondsSinceEpoch;

  bool tryConsume([int tokens = 1]) {
    _refill();
    if (_tokens >= tokens) {
      _tokens -= tokens;
      return true;
    }
    return false;
  }

  void _refill() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsedMs = now - _lastRefillTimestamp;
    
    if (elapsedMs <= 0) return;

    final tokensToAdd = (elapsedMs / 1000.0) * refillRatePerSecond;
    _tokens += tokensToAdd;
    if (_tokens > capacity) {
      _tokens = capacity;
    }
    
    _lastRefillTimestamp = now;
  }
}
