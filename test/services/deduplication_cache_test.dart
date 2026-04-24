import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/config/limits_config.dart';
import 'package:peerchat_secure/src/services/db_service.dart';
import 'package:peerchat_secure/src/services/deduplication_cache.dart';

void main() {
  group('DeduplicationCache in-memory tracking', () {
    late DeduplicationCache cache;

    setUp(() {
      cache = DeduplicationCache(DBService());
    });

    test('hasSeenFingerprint touches entries so recently used keys survive eviction', () {
      const senderId = 'sender';

      for (int i = 0; i < DeduplicationLimits.maxFingerprints; i++) {
        cache.markFingerprint('msg_$i', senderId, 0);
      }

      expect(cache.hasSeenFingerprint('msg_0', senderId, 0), isTrue);

      cache.markFingerprint('overflow', senderId, 0);

      expect(cache.hasSeenFingerprint('msg_0', senderId, 0), isTrue);
      expect(cache.hasSeenFingerprint('msg_1', senderId, 0), isFalse);
      expect(cache.size, DeduplicationLimits.maxFingerprints);
    });

    test('forwarded-to tracking deduplicates peers and reports counts', () {
      expect(cache.hasForwardedTo('message', 'peer-a'), isFalse);
      expect(cache.getForwardCount('message'), 0);

      cache.markForwardedTo('message', 'peer-a');
      cache.markForwardedTo('message', 'peer-a');
      cache.markForwardedTo('message', 'peer-b');

      expect(cache.hasForwardedTo('message', 'peer-a'), isTrue);
      expect(cache.hasForwardedTo('message', 'peer-b'), isTrue);
      expect(cache.hasForwardedTo('message', 'peer-c'), isFalse);
      expect(cache.getForwardCount('message'), 2);
    });

    test('forwarded-to entries use LRU eviction across message ids', () {
      for (int i = 0; i < DeduplicationLimits.maxForwardedToEntries; i++) {
        cache.markForwardedTo('msg_$i', 'peer');
      }

      expect(cache.hasForwardedTo('msg_0', 'peer'), isTrue);

      cache.markForwardedTo('overflow', 'peer');

      expect(cache.hasForwardedTo('msg_0', 'peer'), isTrue);
      expect(cache.hasForwardedTo('msg_1', 'peer'), isFalse);
      expect(cache.hasForwardedTo('overflow', 'peer'), isTrue);
    });
  });
}
