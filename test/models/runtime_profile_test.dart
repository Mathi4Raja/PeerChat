import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/runtime_profile.dart';

void main() {
  group('RuntimeProfile', () {
    test('extension fields expose expected strings', () {
      expect(RuntimeProfile.normalDirect.storageValue, 'normal_direct');
      expect(RuntimeProfile.normalMesh.storageValue, 'normal_mesh');
      expect(RuntimeProfile.emergencyBattery.storageValue, 'emergency_battery');

      expect(RuntimeProfile.normalDirect.shortLabel, 'Standard');
      expect(RuntimeProfile.normalMesh.shortLabel, 'Legacy Mesh');
      expect(RuntimeProfile.emergencyBattery.shortLabel, 'Battery');

      expect(RuntimeProfile.normalDirect.description, contains('Standard'));
      expect(RuntimeProfile.normalMesh.description, contains('Legacy'));
      expect(RuntimeProfile.emergencyBattery.description, contains('Battery'));
    });

    test('runtimeProfileFromStorage normalizes and defaults safely', () {
      expect(
        runtimeProfileFromStorage('normal_mesh'),
        RuntimeProfile.normalDirect,
      );
      expect(
        runtimeProfileFromStorage('emergency_battery'),
        RuntimeProfile.emergencyBattery,
      );
      expect(
        runtimeProfileFromStorage('normal_direct'),
        RuntimeProfile.normalDirect,
      );
      expect(
        runtimeProfileFromStorage('anything_else'),
        RuntimeProfile.normalDirect,
      );
      expect(runtimeProfileFromStorage(null), RuntimeProfile.normalDirect);
    });
  });
}

