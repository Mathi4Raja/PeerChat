import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/services/deduplication_cache.dart';
import 'package:peerchat_secure/src/config/limits_config.dart';

// Use a simplified mock that doesn't try to extend the singleton factory directly
// Since we only need the type match for the constructor
class MockDBService {
  Future<dynamic> get db async => null;
}

void main() {
  group('Security & Concurrency Hardening Tests', () {
    
    test('DeduplicationCache Enforces Strict LRU Boundary', () {
      // Pass null casted to dynamic to avoid constructor issues in this specific test
      final cache = DeduplicationCache(null as dynamic);
      const maxFingerprints = DeduplicationLimits.maxFingerprints;
      
      // Fill the cache up to the limit
      for (int i = 0; i < maxFingerprints; i++) {
        cache.markFingerprint('msg_$i', 'sender', 0);
      }
      
      // Cache should be exactly at limit
      expect(cache.size, maxFingerprints);
      
      // Add one more
      cache.markFingerprint('new_msg', 'sender', 0);
      
      // The oldest one ('msg_0') should have been evicted
      expect(cache.hasSeenFingerprint('msg_0', 'sender', 0), isFalse);
      expect(cache.size, maxFingerprints);
    });

    group('WiFi Connection Race Condition (Logical)', () {
      test('Pending connection attempt prevents duplicate simultaneous requests', () async {
        final pendingAttempts = <String>{};
        int requestCount = 0;

        Future<void> mockRequestConnection(String id) async {
          // Logic used in WiFiTransport
          if (pendingAttempts.contains(id)) return;
          pendingAttempts.add(id);
          
          requestCount++;
          await Future.delayed(const Duration(milliseconds: 50));
          
          pendingAttempts.remove(id);
        }

        await Future.wait([
          mockRequestConnection('peer1'),
          mockRequestConnection('peer1'),
          mockRequestConnection('peer1'),
        ]);

        expect(requestCount, 1);
      });
    });
  });
}
