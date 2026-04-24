import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/models/communication_mode.dart';

void main() {
  test('selectMode chooses emergency broadcast only for sentinel destination', () {
    expect(
      selectMode(destinationId: broadcastEmergencyDestination),
      CommunicationMode.emergencyBroadcast,
    );
    expect(
      selectMode(destinationId: 'peer-123'),
      CommunicationMode.mesh,
    );
  });
}

