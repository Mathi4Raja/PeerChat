import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/route.dart';

void main() {
  group('Route', () {
    test('toMap/fromMap and copyWith work', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final route = Route(
        destinationPeerId: 'dest',
        nextHopPeerId: 'next',
        hopCount: 2,
        lastUsedTimestamp: now,
        lastUpdatedTimestamp: now,
        successCount: 3,
        failureCount: 1,
      );

      final mapped = route.toMap();
      final decoded = Route.fromMap(mapped);
      final copied = route.copyWith(nextHopPeerId: 'other');

      expect(decoded.destinationPeerId, 'dest');
      expect(decoded.nextHopPeerId, 'next');
      expect(decoded.hopCount, 2);
      expect(decoded.successCount, 3);
      expect(decoded.failureCount, 1);
      expect(copied.nextHopPeerId, 'other');
      expect(copied.destinationPeerId, route.destinationPeerId);
    });

    test('preferenceScore rewards recency and success', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final freshGood = Route(
        destinationPeerId: 'd',
        nextHopPeerId: 'n',
        hopCount: 2,
        lastUsedTimestamp: now,
        lastUpdatedTimestamp: now,
        successCount: 10,
        failureCount: 0,
      );
      final oldBad = Route(
        destinationPeerId: 'd',
        nextHopPeerId: 'n',
        hopCount: 2,
        lastUsedTimestamp: now - (60 * 60 * 1000),
        lastUpdatedTimestamp: now,
        successCount: 1,
        failureCount: 9,
      );

      expect(freshGood.preferenceScore, greaterThan(oldBad.preferenceScore));
      expect(oldBad.isStale, isTrue);
      expect(freshGood.isStale, isFalse);
    });
  });
}

