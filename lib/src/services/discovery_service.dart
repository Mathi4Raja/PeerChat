import 'dart:async';
import 'dart:math';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/peer.dart';
import '../models/runtime_profile.dart';
import '../config/timer_config.dart';
import '../config/network_config.dart';
import '../config/protocol_config.dart';

class DiscoveryService {
  final BluetoothClassic _bluetooth = BluetoothClassic();
  StreamController<Peer> _foundController = StreamController.broadcast();
  bool _bluetoothScanning = false;
  StreamSubscription? _scanSubscription;
  Timer? _scanStopTimer;
  Timer? _scanRestartTimer;
  MDnsClient? _mdnsClient;
  String? _localId;
  String? _localName;
  final Random _scanJitterRandom = Random();
  bool _bluetoothDiscoverySuspended = false;

  // Track discovered peers to avoid duplicates
  final Set<String> _discoveredPeerIds = {};

  // Adaptive discovery policy
  int _connectedPeerCount = 0;
  bool _fileTransferActive = false;
  bool _batteryLow = false;
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;
  int _fastBurstUntilTimestamp = 0;
  String _lastPolicySignature = '';

  Stream<Peer> get onPeerFound => _foundController.stream;

  Future<void> start(String myId, int port, {String name = 'PeerChat'}) async {
    _localId = myId;
    _localName = name;
    // Start mDNS discovery lookup (passive)
    await _startMdnsDiscovery(myId, port, name);

    // Start Bluetooth discovery
    await _startBluetoothDiscovery(myId, name);
  }

  void startFastDiscoveryBurst({
    Duration window = DiscoveryTimerConfig.fastBurstWindow,
  }) {
    if (_runtimeProfile == RuntimeProfile.emergencyBattery) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final burstUntil = now + window.inMilliseconds;
    if (burstUntil > _fastBurstUntilTimestamp) {
      _fastBurstUntilTimestamp = burstUntil;
    }

    final localId = _localId;
    final localName = _localName;
    if (localId == null || localName == null) return;

    _scanRestartTimer?.cancel();
    if (!_bluetoothScanning) {
      _startBluetoothDiscovery(localId, localName);
    }
  }

  Future<void> _startMdnsDiscovery(String myId, int port, String name) async {
    try {
      // Discover peers using multicast_dns (Passive lookup only)
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      debugPrint('mDNS discovery lookup started');

      _mdnsClient!.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(NetworkConfig.mdnsServiceType),
      ).listen((ptr) {
        _mdnsClient!.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        ).listen((srv) {
          _mdnsClient!.lookup<TxtResourceRecord>(
            ResourceRecordQuery.text(ptr.domainName),
          ).listen((txt) {
            final props = _parseTxt(txt.text);
            final peerId = props['id'];
            if (peerId == null || peerId == _localId) return;

            final peerName = props['name'] ?? 'Unknown';
            final peer = Peer(
              id: peerId,
              displayName: peerName,
              address: '${srv.target}:${srv.port}',
              lastSeen: DateTime.now().millisecondsSinceEpoch,
              hasApp: true,
              isWiFi: true,
              isBluetooth: false,
            );
            _foundController.add(peer);
          });
        });
      });
    } catch (e) {
      debugPrint('DiscoveryService: mDNS discovery lookup error: $e');
    }
  }

  Map<String, String> _parseTxt(String text) {
    final map = <String, String>{};
    final parts = text.split(RegExp(r'[\n\x00]'));
    for (final part in parts) {
      final kv = part.split('=');
      if (kv.length == 2) {
        map[kv[0]] = kv[1];
      }
    }
    return map;
  }

  Future<void> _startBluetoothDiscovery(String myId, String name) async {
    if (_bluetoothScanning || _bluetoothDiscoverySuspended) return;

    try {
      final permissionGranted = await _bluetooth.initPermissions();
      if (!permissionGranted) {
        _scheduleBluetoothRestart(myId, name);
        return;
      }

      _bluetoothScanning = true;
      _scanRestartTimer?.cancel();
      _scanStopTimer?.cancel();

      final bondedDevices = await _bluetooth.getPairedDevices();
      for (final device in bondedDevices) {
        _addBluetoothPeer(device);
      }

      await _bluetooth.startScan();

      _scanSubscription = _bluetooth.onDeviceDiscovered().listen((device) {
        _addBluetoothPeer(device);
      });

      _scanStopTimer = Timer(_activeScanDuration(), () async {
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        await _bluetooth.stopScan();
        _bluetoothScanning = false;
        _scheduleBluetoothRestart(myId, name);
      });
    } catch (e) {
      _bluetoothScanning = false;
      _scheduleBluetoothRestart(myId, name);
    }
  }

  void _scheduleBluetoothRestart(String myId, String name) {
    if (_bluetoothDiscoverySuspended) return;
    _scanRestartTimer?.cancel();
    _scanRestartTimer = Timer(_nextScanIntervalWithJitter(), () {
      _startBluetoothDiscovery(myId, name);
    });
  }

  Future<void> suspendBluetoothDiscovery() async {
    _bluetoothDiscoverySuspended = true;
    _scanStopTimer?.cancel();
    _scanRestartTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    try {
      await _bluetooth.stopScan();
    } catch (e) {
      debugPrint('DiscoveryService: stopScan failed: $e');
    }
    _bluetoothScanning = false;
  }

  Future<void> resumeBluetoothDiscovery() async {
    if (!_bluetoothDiscoverySuspended) return;
    _bluetoothDiscoverySuspended = false;
    final localId = _localId;
    final localName = _localName;
    if (localId == null || localName == null) return;
    await _startBluetoothDiscovery(localId, localName);
  }

  void updateAdaptiveDiscoveryPolicy({
    required int connectedPeerCount,
    required bool fileTransferActive,
    required bool batteryLow,
    required RuntimeProfile runtimeProfile,
  }) {
    final signature = '$connectedPeerCount|$fileTransferActive|$batteryLow|${runtimeProfile.storageValue}';
    _connectedPeerCount = connectedPeerCount;
    _fileTransferActive = fileTransferActive;
    _batteryLow = batteryLow;
    _runtimeProfile = runtimeProfile;

    if (signature != _lastPolicySignature) {
      _lastPolicySignature = signature;
      debugPrint('Discovery policy updated: profile=${_runtimeProfile.storageValue}');
    }
  }

  Duration _nextScanIntervalWithJitter() {
    if (_isFastBurstActive) {
      return DiscoveryTimerConfig.fastBurstRestartInterval;
    }
    return DiscoveryTimerConfig.nextScanIntervalWithJitter(
      runtimeProfile: _runtimeProfile,
      connectedPeerCount: _connectedPeerCount,
      fileTransferActive: _fileTransferActive,
      batteryLow: _batteryLow,
      random: _scanJitterRandom,
    );
  }

  Duration _activeScanDuration() {
    if (_isFastBurstActive) {
      return DiscoveryTimerConfig.fastBurstActiveScanDuration;
    }
    return DiscoveryTimerConfig.activeScanDuration(
      runtimeProfile: _runtimeProfile,
      connectedPeerCount: _connectedPeerCount,
      fileTransferActive: _fileTransferActive,
      batteryLow: _batteryLow,
    );
  }

  bool get _isFastBurstActive {
    if (_runtimeProfile == RuntimeProfile.emergencyBattery) return false;
    return DateTime.now().millisecondsSinceEpoch < _fastBurstUntilTimestamp;
  }

  void _addBluetoothPeer(Device device) {
    final peerId = device.address;
    final peerName = device.name ?? 'Unknown Device';

    if (_discoveredPeerIds.contains(peerId)) return;

    if (device.name != null && device.name!.isNotEmpty && _isValidMeshNode(device)) {
      if (device.name == _localName) return;
      _discoveredPeerIds.add(peerId);

      final peer = Peer(
        id: peerId,
        displayName: peerName,
        address: peerId,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        hasApp: false,
        isWiFi: false,
        isBluetooth: true,
      );
      _foundController.add(peer);
    }
  }

  void addWiFiDirectPeer(String endpointId, String endpointName) {
    if (_discoveredPeerIds.contains(endpointId)) return;
    _discoveredPeerIds.add(endpointId);

    final peer = Peer(
      id: endpointId,
      displayName: endpointName,
      address: endpointId,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      hasApp: true,
      isWiFi: true,
      isBluetooth: false,
    );
    _foundController.add(peer);
  }

  bool _isValidMeshNode(Device device) {
    final name = device.name?.toLowerCase() ?? '';
    if (_containsAnyKeyword(name, DeviceHeuristicConfig.nonMeshAudioKeywords)) return false;
    if (_containsAnyKeyword(name, DeviceHeuristicConfig.nonMeshWearableKeywords)) return false;
    if (_containsAnyKeyword(name, DeviceHeuristicConfig.nonMeshVehicleKeywords)) return false;
    if (_containsAnyKeyword(name, DeviceHeuristicConfig.nonMeshPeripheralKeywords)) return false;
    return true;
  }

  bool _containsAnyKeyword(String value, List<String> keywords) {
    for (final keyword in keywords) {
      if (value.contains(keyword)) return true;
    }
    return false;
  }

  Future<void> stop() async {
    _mdnsClient?.stop();
    _mdnsClient = null;

    _scanStopTimer?.cancel();
    _scanRestartTimer?.cancel();
    await _scanSubscription?.cancel();
    try {
      await _bluetooth.stopScan();
    } catch (_) {}
    _bluetoothScanning = false;

    await _foundController.close();
    _foundController = StreamController.broadcast();
  }

  Future<void> dispose() async {
    await stop();
    await _foundController.close();
  }
}
