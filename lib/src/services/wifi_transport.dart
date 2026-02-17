import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'transport_service.dart';

class WiFiTransport implements TransportService {
  final Nearby _nearby = Nearby();
  final StreamController<TransportMessage> _messageController = StreamController.broadcast();
  final Map<String, String> _connectedPeers = {}; // endpointId -> peerId
  final Function(String peerId, String address)? onPeerDiscovered;
  
  // Callback for when connection is established
  Function(String transportId)? onConnectionEstablished;
  
  // Keepalive mechanism
  Timer? _keepaliveTimer;
  static const Duration keepAliveInterval = Duration(seconds: 20);
  static final Uint8List keepAlivePacket = Uint8List.fromList([0xFF, 0xFF]); // Special keepalive marker
  
  String? _localName;
  bool _isAdvertising = false;
  bool _isDiscovering = false;

  WiFiTransport({this.onPeerDiscovered});

  @override
  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  @override
  Future<void> init() async {
    try {
      // Request necessary permissions
      await _requestPermissions();

      // Start advertising and discovering
      await _startAdvertising();
      await _startDiscovery();
      
      // Start keepalive timer
      _startKeepalive();
    } catch (e) {
      debugPrint('Error initializing WiFi Direct: $e');
    }
  }
  
  void _startKeepalive() {
    _keepaliveTimer = Timer.periodic(keepAliveInterval, (timer) {
      _sendKeepalives();
    });
    debugPrint('WiFi Direct keepalive started (every ${keepAliveInterval.inSeconds}s)');
  }
  
  void _sendKeepalives() {
    if (_connectedPeers.isEmpty) return;
    
    debugPrint('Sending keepalive to ${_connectedPeers.length} peers');
    for (final endpointId in _connectedPeers.keys) {
      try {
        _nearby.sendBytesPayload(endpointId, keepAlivePacket);
      } catch (e) {
        debugPrint('Error sending keepalive to $endpointId: $e');
      }
    }
  }
  
  void setLocalIdentity(String peerId, String name) {
    _localName = name;
    
    // Restart advertising with new name if already advertising
    if (_isAdvertising) {
      _restartAdvertising();
    }
  }
  
  Future<void> _restartAdvertising() async {
    try {
      // Stop current advertising
      await _nearby.stopAdvertising();
      _isAdvertising = false;
      
      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Start with new name
      await _startAdvertising();
    } catch (e) {
      debugPrint('Error restarting WiFi Direct advertising: $e');
    }
  }

  Future<void> _requestPermissions() async {
    // Request location permissions explicitly
    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      debugPrint('Location permission not granted, requesting again...');
      await Permission.location.request();
    }
    
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
    ].request();
    
    debugPrint('Permissions requested');
  }

  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;

    try {
      final strategy = Strategy.P2P_CLUSTER;
      final userName = _localName ?? 'PeerChat User';
      
      await _nearby.startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );

      _isAdvertising = true;
      debugPrint('WiFi Direct advertising started as: $userName');
    } catch (e) {
      debugPrint('Error starting WiFi Direct advertising: $e');
    }
  }

  Future<void> _startDiscovery() async {
    if (_isDiscovering) return;

    try {
      final strategy = Strategy.P2P_CLUSTER;
      final userName = _localName ?? 'PeerChat User';
      
      await _nearby.startDiscovery(
        userName,
        strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
      );

      _isDiscovering = true;
      debugPrint('WiFi Direct discovery started');
    } catch (e) {
      debugPrint('Error starting WiFi Direct discovery: $e');
    }
  }

  void _onEndpointFound(String endpointId, String endpointName, String serviceId) {
    debugPrint('WiFi Direct endpoint found: $endpointId ($endpointName)');
    
    // Notify discovery service about the peer
    if (onPeerDiscovered != null) {
      onPeerDiscovered!(endpointId, endpointName);
    }
    
    // Request connection
    final userName = _localName ?? 'PeerChat User';
    _nearby.requestConnection(
      userName,
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  void _onEndpointLost(String? endpointId) {
    debugPrint('WiFi Direct endpoint lost: $endpointId');
    if (endpointId != null) {
      _connectedPeers.remove(endpointId);
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    debugPrint('WiFi Direct connection initiated: $endpointId');
    
    // Auto-accept connections
    _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) {
        _handleIncomingPayload(endpointId, payload);
      },
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      debugPrint('WiFi Direct connected: $endpointId');
      _connectedPeers[endpointId] = endpointId; // Use endpointId as peerId for now
      
      // Notify connection established
      if (onConnectionEstablished != null) {
        onConnectionEstablished!(endpointId);
      }
    } else {
      debugPrint('WiFi Direct connection failed: $endpointId');
      _connectedPeers.remove(endpointId);
    }
  }

  void _onDisconnected(String endpointId) {
    debugPrint('WiFi Direct disconnected: $endpointId');
    _connectedPeers.remove(endpointId);
  }

  void _handleIncomingPayload(String endpointId, Payload payload) {
    try {
      if (payload.type == PayloadType.BYTES && payload.bytes != null) {
        final bytes = Uint8List.fromList(payload.bytes!);
        
        // Check if it's a keepalive packet
        if (bytes.length == 2 && bytes[0] == 0xFF && bytes[1] == 0xFF) {
          debugPrint('Received keepalive from $endpointId');
          return; // Don't forward keepalive packets
        }
        
        final message = TransportMessage(
          fromPeerId: endpointId,
          fromAddress: endpointId,
          data: bytes,
        );
        _messageController.add(message);
      }
    } catch (e) {
      debugPrint('Error handling WiFi Direct payload: $e');
    }
  }

  @override
  Future<bool> sendMessage(String peerId, Uint8List data) async {
    debugPrint('WiFiTransport.sendMessage to $peerId');
    
    // Find endpoint ID for peer
    String? endpointId;
    for (final entry in _connectedPeers.entries) {
      if (entry.value == peerId || entry.key == peerId) {
        endpointId = entry.key;
        break;
      }
    }

    if (endpointId == null) {
      debugPrint('  No endpoint found for $peerId');
      debugPrint('  Connected peers: $_connectedPeers');
      return false;
    }

    try {
      debugPrint('  Sending ${data.length} bytes to endpoint $endpointId...');
      await _nearby.sendBytesPayload(endpointId, data);
      debugPrint('  Data sent successfully');
      return true;
    } catch (e) {
      debugPrint('  Error sending: $e');
      return false;
    }
  }

  @override
  List<String> getConnectedPeerIds() {
    return _connectedPeers.values.toList();
  }

  @override
  Future<void> dispose() async {
    _keepaliveTimer?.cancel();
    if (_isAdvertising) {
      await _nearby.stopAdvertising();
      _isAdvertising = false;
    }
    if (_isDiscovering) {
      await _nearby.stopDiscovery();
      _isDiscovering = false;
    }
    await _nearby.stopAllEndpoints();
    await _messageController.close();
  }
}
