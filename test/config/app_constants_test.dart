import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/config/identity_ui_config.dart';
import 'package:peerchat_secure/src/config/limits_config.dart';
import 'package:peerchat_secure/src/config/network_config.dart';
import 'package:peerchat_secure/src/config/protocol_config.dart';

void main() {
  test('network and protocol constants remain aligned', () {
    expect(NetworkConfig.discoveryPort, 9000);
    expect(NetworkConfig.mdnsServiceType, '_peerchat._tcp');
    expect(NetworkConfig.mdnsServiceQuery, '_peerchat._tcp.local');

    expect(ProtocolConfig.keepAlivePacketLength, 2);
    expect(ProtocolConfig.keepAlivePacket, [0xFF, 0xFF]);
    expect(ProtocolConfig.keepAliveByte, 0xFF);
  });

  test('identity and limit constants remain sane', () {
    expect(IdentityUiConfig.defaultDisplayName, isNotEmpty);
    expect(IdentityUiConfig.shortIdLength, 8);
    expect(IdPreviewConfig.leadingChars, lessThan(IdPreviewConfig.fullDisplayThreshold));

    expect(MessageLimits.wireIdLength, 36);
    expect(MessageLimits.ttlMin, lessThanOrEqualTo(MessageLimits.ttlMax));
    expect(QueueLimits.maxRetries, greaterThan(0));
    expect(BroadcastLimits.maxPerMinute, greaterThan(0));
  });

  test('error token lists are present for discovery heuristics', () {
    expect(WiFiDiscoveryErrorConfig.missingPermissionTokens, isNotEmpty);
    expect(WiFiDiscoveryErrorConfig.locationDisabledTokens, isNotEmpty);
    expect(DeviceHeuristicConfig.bondedSkipKeywords, isNotEmpty);
    expect(DeviceHeuristicConfig.nonMeshAudioKeywords, isNotEmpty);
  });
}

