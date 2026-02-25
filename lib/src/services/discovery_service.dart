import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:nsd/nsd.dart';
import '../models/peer.dart';
import '../models/runtime_profile.dart';

class DiscoveryService {
  final MDnsClient _mdns = MDnsClient();
  final FlutterBlueClassic _bluetooth = FlutterBlueClassic();
  StreamController<Peer> _foundController = StreamController.broadcast();
  bool _advertising = false;
  bool _bluetoothScanning = false;
  StreamSubscription? _scanSubscription;
  Registration? _nsdRegistration;
  String? _localId;
  String? _localName;
  final Random _scanJitterRandom = Random();

  // Track discovered peers to avoid duplicates
  final Set<String> _discoveredPeerIds = {};

  // Adaptive discovery policy (Phase 9 baseline)
  int _connectedPeerCount = 0;
  bool _fileTransferActive = false;
  bool _batteryLow = false;
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;
  String _lastPolicySignature = '';

  Stream<Peer> get onPeerFound => _foundController.stream;

  Future<void> start(String myId, int port, {String name = 'PeerChat'}) async {
    _localId = myId;
    _localName = name;
    // Start mDNS discovery (for WiFi)
    await _startMdnsDiscovery(myId, port, name);

    // Start Bluetooth discovery
    await _startBluetoothDiscovery(myId, name);
  }

  Future<void> _startMdnsDiscovery(String myId, int port, String name) async {
    try {
      await _mdns.start();

      // Advertise our service using NSD (Network Service Discovery)
      if (!_advertising) {
        _advertising = true;
        try {
          // Register service on local network
          _nsdRegistration = await register(
            Service(
              name:
                  'PeerChat', // Name will be appended with unique ID by OS usually
              type: '_peerchat._tcp',
              port: 9000, // We listen on port 9000
              txt: {
                'id': Uint8List.fromList(utf8.encode(myId)),
                'name': Uint8List.fromList(utf8.encode(name)),
              },
            ),
          );
          debugPrint(
              'mDNS service registered: ${_nsdRegistration?.service.name}');
        } catch (e) {
          debugPrint('Error registering mDNS service: $e');
          _advertising = false;
        }
      }
      // Browse for _peerchat._tcp local services
      _mdns
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('_peerchat._tcp.local'))
          .listen((ptr) async {
        final String domainName = ptr.domainName;
        // resolve SRV
        await for (final SrvResourceRecord srv
            in _mdns.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(domainName))) {
          final target = srv.target;
          final srvPort = srv.port;
          // resolve A/AAAA
          await for (final IPAddressResourceRecord ip
              in _mdns.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(target))) {
            final addr = ip.address.address;
            // For this MVP we expect TXT records with id and name
            await for (final TxtResourceRecord txt
                in _mdns.lookup<TxtResourceRecord>(
                    ResourceRecordQuery.text(domainName))) {
              final map = <String, String>{};
              for (var s in txt.text.split('\n')) {
                // Fix: base64 IDs often contain '=', so only split on the FIRST '='
                final index = s.indexOf('=');
                if (index != -1) {
                  final key = s.substring(0, index);
                  final value = s.substring(index + 1);
                  map[key] = value;
                }
              }
              final id = map['id'] ?? 'unknown';

              // CRITICAL: Robust self-filter
              if (id == _localId || id == 'unknown') continue;

              final peerName = map['name'] ?? target;
              final peer = Peer(
                id: id,
                displayName: peerName,
                address: '$addr:$srvPort',
                lastSeen: DateTime.now().millisecondsSinceEpoch,
                hasApp: true, // mDNS discovery means they have the app
                isWiFi: true,
                isBluetooth: false,
              );
              _foundController.add(peer);
            }
          }
        }
      });
    } catch (e) {
      // Ignore mDNS errors
    }
  }

  Future<void> _startBluetoothDiscovery(String myId, String name) async {
    if (_bluetoothScanning) return;

    try {
      // Check if Bluetooth is supported
      final isSupported = await _bluetooth.isSupported;
      if (!isSupported) return;

      // Check if Bluetooth is enabled
      final isEnabled = await _bluetooth.isEnabled;
      if (!isEnabled) {
        // Try to enable Bluetooth
        _bluetooth.turnOn();
        // Wait a bit for Bluetooth to turn on
        await Future.delayed(const Duration(seconds: 2));
      }

      _bluetoothScanning = true;

      // Get bonded (paired) devices first
      final bondedDevices = await _bluetooth.bondedDevices;
      if (bondedDevices != null) {
        for (final device in bondedDevices) {
          _addBluetoothPeer(device);
        }
      }

      // Start scanning for nearby devices
      _bluetooth.startScan();

      // Listen to scan results
      _scanSubscription = _bluetooth.scanResults.listen((device) {
        _addBluetoothPeer(device);
      });

      // Stop scan after adaptive active window and restart
      Future.delayed(_activeScanDuration(), () async {
        await _scanSubscription?.cancel();
        _bluetooth.stopScan();
        _bluetoothScanning = false;
        // Restart discovery after adaptive delay.
        Future.delayed(_nextScanIntervalWithJitter(), () {
          _startBluetoothDiscovery(myId, name);
        });
      });
    } catch (e) {
      _bluetoothScanning = false;
      // Try again later on failures to keep discovery alive.
      Future.delayed(_nextScanIntervalWithJitter(), () {
        _startBluetoothDiscovery(myId, name);
      });
    }
  }

  /// Update adaptive discovery policy.
  ///
  /// Rule:
  /// - 0 connections: 5s
  /// - 1-2 connections: 15s
  /// - 3+ connections: 30s (+ jitter)
  /// - Active transfer: disable throttle (5s baseline)
  /// - Low battery: double intervals
  void updateAdaptiveDiscoveryPolicy({
    required int connectedPeerCount,
    required bool fileTransferActive,
    required bool batteryLow,
    required RuntimeProfile runtimeProfile,
  }) {
    final signature =
        '$connectedPeerCount|$fileTransferActive|$batteryLow|${runtimeProfile.storageValue}';
    _connectedPeerCount = connectedPeerCount;
    _fileTransferActive = fileTransferActive;
    _batteryLow = batteryLow;
    _runtimeProfile = runtimeProfile;

    if (signature != _lastPolicySignature) {
      _lastPolicySignature = signature;
      final nextInterval = _nextScanIntervalWithJitter();
      debugPrint(
          'Discovery policy updated: profile=${_runtimeProfile.storageValue} connected=$_connectedPeerCount transfer=$_fileTransferActive batteryLow=$_batteryLow nextScan=${nextInterval.inSeconds}s');
    }
  }

  Duration _nextScanIntervalWithJitter() {
    Duration base;
    switch (_runtimeProfile) {
      case RuntimeProfile.normalMesh:
        if (_connectedPeerCount <= 0) {
          base = const Duration(seconds: 5);
        } else if (_connectedPeerCount <= 2) {
          base = const Duration(seconds: 7);
        } else {
          base = const Duration(seconds: 10);
        }
        break;
      case RuntimeProfile.emergencyBattery:
        if (_connectedPeerCount <= 0) {
          base = const Duration(seconds: 20);
        } else if (_connectedPeerCount <= 2) {
          base = const Duration(seconds: 35);
        } else {
          base = const Duration(seconds: 60);
        }
        break;
      case RuntimeProfile.normalDirect:
        if (_fileTransferActive) {
          base = const Duration(seconds: 5);
        } else if (_connectedPeerCount <= 0) {
          base = const Duration(seconds: 5);
        } else if (_connectedPeerCount <= 2) {
          base = const Duration(seconds: 15);
        } else {
          base = const Duration(seconds: 30);
        }
        break;
    }

    if (_batteryLow && _runtimeProfile != RuntimeProfile.emergencyBattery) {
      base = Duration(milliseconds: base.inMilliseconds * 2);
    }

    final jitterMs = _scanJitterRandom.nextInt(3001); // 0-3000ms
    return Duration(milliseconds: base.inMilliseconds + jitterMs);
  }

  Duration _activeScanDuration() {
    if (_runtimeProfile == RuntimeProfile.emergencyBattery) {
      return _batteryLow
          ? const Duration(seconds: 2)
          : const Duration(seconds: 3);
    }

    if (_runtimeProfile == RuntimeProfile.normalMesh) {
      if (_connectedPeerCount <= 0) {
        return const Duration(seconds: 10);
      }
      if (_connectedPeerCount <= 2) {
        return const Duration(seconds: 8);
      }
      return const Duration(seconds: 6);
    }

    if (_fileTransferActive) {
      return const Duration(seconds: 10);
    }
    if (_connectedPeerCount <= 0) {
      return const Duration(seconds: 8);
    }
    if (_connectedPeerCount <= 2) {
      return const Duration(seconds: 6);
    }
    return _batteryLow
        ? const Duration(seconds: 3)
        : const Duration(seconds: 4);
  }

  void _addBluetoothPeer(BluetoothDevice device) {
    // Use device address as peer ID
    final peerId = device.address;
    final peerName = device.name ?? 'Unknown Device';

    // Skip if already discovered
    if (_discoveredPeerIds.contains(peerId)) {
      return;
    }

    // Filter: Only add devices that can act as mesh nodes
    if (device.name != null &&
        device.name!.isNotEmpty &&
        _isValidMeshNode(device)) {
      // CRITICAL: Filter out self by name if possible
      if (device.name == _localName) return;

      _discoveredPeerIds.add(peerId);

      // Emit unverified Bluetooth peer so it shows up in "Unconnected" list
      final peer = Peer(
        id: peerId,
        displayName: peerName,
        address: peerId,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        hasApp: false, // Don't know if they have the app yet
        isWiFi: false,
        isBluetooth: true,
      );
      _foundController.add(peer);

      debugPrint('BT device found and emitted: $peerName ($peerId)');
    }
  }

  // Add peer from WiFi Direct discovery
  void addWiFiDirectPeer(String endpointId, String endpointName) {
    // Skip if already discovered
    if (_discoveredPeerIds.contains(endpointId)) {
      return;
    }

    _discoveredPeerIds.add(endpointId);

    // NOTE: WiFi Direct peers ARE emitted because they were discovered
    // via PeerChat's nearby_connections advertising — they DO have the app.
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

  bool _isValidMeshNode(BluetoothDevice device) {
    // Check device type/class to filter out non-mesh-capable devices
    // BluetoothDeviceType: unknown, classic, le, dual
    // We want classic or dual mode devices (phones, tablets, computers)

    // Filter by device name patterns (common exclusions)
    final name = device.name?.toLowerCase() ?? '';

    // Exclude audio devices
    if (name.contains('headphone') ||
        name.contains('earbuds') ||
        name.contains('airpods') ||
        name.contains('buds') ||
        name.contains('speaker') ||
        name.contains('soundbar') ||
        name.contains('audio') ||
        name.contains('beats') ||
        name.contains('bose') ||
        name.contains('sony wh') ||
        name.contains('jbl')) {
      return false;
    }

    // Exclude wearables
    if (name.contains('watch') ||
        name.contains('band') ||
        name.contains('fit') ||
        name.contains('tracker')) {
      return false;
    }

    // Exclude car systems
    if (name.contains('car') ||
        name.contains('auto') ||
        name.contains('vehicle')) {
      return false;
    }

    // Exclude IoT devices
    if (name.contains('tv') ||
        name.contains('remote') ||
        name.contains('controller') ||
        name.contains('gamepad') ||
        name.contains('keyboard') ||
        name.contains('mouse')) {
      return false;
    }

    // Include devices with typical phone/tablet/computer names
    // Most phones show as "User's Phone", "Galaxy S21", "iPhone", "Pixel", etc.
    // Tablets: "iPad", "Galaxy Tab", etc.
    // Computers: "User's PC", "MacBook", etc.

    // If device type is classic or dual, and name doesn't match exclusions, include it
    // This will catch most phones, tablets, and computers
    return true;
  }

  Future<void> stop() async {
    // Stop mDNS
    _mdns.stop();
    if (_nsdRegistration != null) {
      await unregister(_nsdRegistration!);
      _nsdRegistration = null;
    }
    _advertising = false;

    // Stop Bluetooth scanning
    await _scanSubscription?.cancel();
    _bluetooth.stopScan();
    _bluetoothScanning = false;

    await _foundController.close();
    _foundController = StreamController.broadcast();
  }
}
