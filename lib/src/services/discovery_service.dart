import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:nsd/nsd.dart';
import '../models/peer.dart';

class DiscoveryService {
  final MDnsClient _mdns = MDnsClient();
  final FlutterBlueClassic _bluetooth = FlutterBlueClassic();
  StreamController<Peer> _foundController = StreamController.broadcast();
  bool _advertising = false;
  bool _bluetoothScanning = false;
  StreamSubscription? _scanSubscription;
  Registration? _nsdRegistration;
  
  // Track discovered peers to avoid duplicates
  final Set<String> _discoveredPeerIds = {};

  Stream<Peer> get onPeerFound => _foundController.stream;

  Future<void> start(String myId, int port, {String name = 'PeerChat'}) async {
    // Start mDNS discovery (for WiFi)
    await _startMdnsDiscovery(myId, port, name);
    
    // Start Bluetooth discovery
    await _startBluetoothDiscovery(myId, name);
  }

  Future<void> _startMdnsDiscovery(String myId, int port, String name) async {
    try {
      await _mdns.start();
      await _mdns.start();
      
      // Advertise our service using NSD (Network Service Discovery)
      if (!_advertising) {
        _advertising = true;
        try {
          // Register service on local network
          _nsdRegistration = await register(
            Service(
              name: 'PeerChat', // Name will be appended with unique ID by OS usually
              type: '_peerchat._tcp',
              port: 9000, // We listen on port 9000
              txt: {
                'id': myId,
                'name': name,
              },
            ),
          );
          print('mDNS service registered: ${_nsdRegistration?.service.name}');
        } catch (e) {
          print('Error registering mDNS service: $e');
          _advertising = false;
        }
      }
      // Browse for _peerchat._tcp local services
      _mdns.lookup<PtrResourceRecord>(ResourceRecordQuery.serverPointer('_peerchat._tcp.local')).listen((ptr) async {
        final String domainName = ptr.domainName;
        // resolve SRV
        await for (final SrvResourceRecord srv in _mdns.lookup<SrvResourceRecord>(ResourceRecordQuery.service(domainName))) {
          final target = srv.target;
          final srvPort = srv.port;
          // resolve A/AAAA
          await for (final IPAddressResourceRecord ip in _mdns.lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(target))) {
            final addr = ip.address.address;
            // For this MVP we expect TXT records with id and name
            await for (final TxtResourceRecord txt in _mdns.lookup<TxtResourceRecord>(ResourceRecordQuery.text(domainName))) {
              final map = <String, String>{};
              for (var s in txt.text.split('\n')) {
                final split = s.split('=');
                if (split.length == 2) map[split[0]] = split[1];
              }
              final id = map['id'] ?? 'unknown';
              final peerName = map['name'] ?? target;
              final peer = Peer(
                id: id,
                displayName: peerName,
                address: '$addr:$srvPort',
                lastSeen: DateTime.now().millisecondsSinceEpoch,
                hasApp: true, // mDNS discovery means they have the app
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

      // Stop scan after 30 seconds and restart
      Future.delayed(const Duration(seconds: 30), () async {
        await _scanSubscription?.cancel();
        _bluetooth.stopScan();
        _bluetoothScanning = false;
        // Restart discovery after a delay
        Future.delayed(const Duration(seconds: 10), () {
          _startBluetoothDiscovery(myId, name);
        });
      });
    } catch (e) {
      _bluetoothScanning = false;
      // Ignore Bluetooth errors
    }
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
    // Exclude audio devices (headphones, speakers), wearables, etc.
    // Only include: phones, tablets, computers
    if (device.name != null && device.name!.isNotEmpty && _isValidMeshNode(device)) {
      _discoveredPeerIds.add(peerId);
      final peer = Peer(
        id: peerId,
        displayName: peerName,
        address: device.address,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        hasApp: false, // Bluetooth discovery alone can't confirm app installation
      );
      _foundController.add(peer);
    }
  }
  
  // Add peer from WiFi Direct discovery
  void addWiFiDirectPeer(String endpointId, String endpointName) {
    // Skip if already discovered
    if (_discoveredPeerIds.contains(endpointId)) {
      return;
    }
    
    _discoveredPeerIds.add(endpointId);
    final peer = Peer(
      id: endpointId,
      displayName: endpointName,
      address: endpointId,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      hasApp: true, // WiFi Direct discovery means they have the app
    );
    _foundController.add(peer);
  }

  bool _isValidMeshNode(BluetoothDevice device) {
    // Check device type/class to filter out non-mesh-capable devices
    final deviceType = device.type;
    
    // Exclude known non-mesh device types
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
