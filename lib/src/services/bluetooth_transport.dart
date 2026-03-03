import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/timer_config.dart';
import '../config/protocol_config.dart';
import 'transport_service.dart';

class BluetoothTransport implements TransportService {
  final FlutterBlueClassic _bluetooth = FlutterBlueClassic();
  final StreamController<TransportMessage> _messageController =
      StreamController.broadcast();
  final Map<String, BluetoothConnection> _connections = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Set<String> _connectingDevices =
      {}; // Track devices we're connecting to
  static final RegExp _bluetoothMacPattern =
      RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

  // Callback for when connection is established
  Function(String transportId)? onConnectionEstablished;

  // Callback for when connection is lost
  Function(String transportId)? onConnectionLost;

  Timer? _reconnectTimer;

  @override
  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  @override
  Future<void> init() async {
    try {
      // Request Bluetooth permissions
      await _requestPermissions();

      // Check if Bluetooth is supported
      final isSupported = await _bluetooth.isSupported;
      if (!isSupported) {
        debugPrint('Bluetooth is not supported on this device');
        return;
      }

      // Enable Bluetooth if not enabled
      final isEnabled = await _bluetooth.isEnabled;
      if (!isEnabled) {
        debugPrint('Bluetooth is disabled, attempting to enable...');
        _bluetooth.turnOn();
        await Future.delayed(BluetoothTimerConfig.enableAfterTurnOnDelay);
      }

      // Connect to bonded devices only (more reliable)
      await _connectToBondedDevices();

      // Start periodic reconnection attempts
      _startReconnectionTimer();

      debugPrint('Bluetooth transport initialized');
    } catch (e) {
      debugPrint('Error initializing Bluetooth: $e');
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
    ].request();
  }

  Future<void> _connectToBondedDevices() async {
    try {
      debugPrint('Connecting to bonded (paired) devices...');
      final bondedDevices = await _bluetooth.bondedDevices;

      if (bondedDevices == null || bondedDevices.isEmpty) {
        debugPrint(
            'No bonded devices found. Please pair devices in Android settings first.');
        return;
      }

      debugPrint('Found ${bondedDevices.length} bonded devices');

      // Filter to only connect to devices that look like phones/tablets
      final potentialPeerDevices = bondedDevices.where((device) {
        final name = device.name?.toLowerCase() ?? '';
        if (_containsAnyKeyword(
            name, DeviceHeuristicConfig.bondedSkipKeywords)) {
          return false;
        }
        return _containsAnyKeyword(
            name, DeviceHeuristicConfig.bondedPhoneHints);
      }).toList();

      if (potentialPeerDevices.isEmpty) {
        debugPrint('No phone/tablet devices found in bonded list');
        debugPrint('All bonded devices:');
        for (final device in bondedDevices) {
          debugPrint('  - ${device.name ?? 'Unknown'} (${device.address})');
        }
        return;
      }

      debugPrint(
          'Filtered to ${potentialPeerDevices.length} potential peer devices:');
      for (final device in potentialPeerDevices) {
        debugPrint('  - ${device.name ?? 'Unknown'} (${device.address})');
        await _connectToPeer(device);
      }
    } catch (e) {
      debugPrint('Error connecting to bonded devices: $e');
    }
  }

  bool _containsAnyKeyword(String value, List<String> keywords) {
    for (final keyword in keywords) {
      if (value.contains(keyword)) return true;
    }
    return false;
  }

  Future<void> _connectToPeer(BluetoothDevice device) async {
    // Skip if already connected or connecting
    if (_connections.containsKey(device.address) ||
        _connectingDevices.contains(device.address)) {
      return;
    }

    _connectingDevices.add(device.address);

    try {
      debugPrint(
          'Attempting Bluetooth connection to ${device.address} (${device.name})...');

      final connection = await _bluetooth.connect(device.address).timeout(
        BluetoothTimerConfig.connectTimeout,
        onTimeout: () {
          debugPrint('Bluetooth connection timeout: ${device.address}');
          return null;
        },
      );

      if (connection == null) {
        debugPrint(
            'Bluetooth connection failed: null connection for ${device.address}');
        _connectingDevices.remove(device.address);
        return;
      }

      if (!connection.isConnected) {
        debugPrint(
            'Bluetooth connection failed: not connected for ${device.address}');
        _connectingDevices.remove(device.address);
        return;
      }

      _connections[device.address] = connection;
      _connectingDevices.remove(device.address);
      debugPrint('✓ Bluetooth connected: ${device.address}');

      // Notify connection established
      if (onConnectionEstablished != null) {
        onConnectionEstablished!(device.address);
      }

      // Listen for incoming data
      final subscription = connection.input?.listen(
        (data) {
          _handleIncomingData(device.address, data);
        },
        onDone: () {
          debugPrint('Bluetooth connection closed: ${device.address}');
          _connections.remove(device.address);
          _subscriptions[device.address]?.cancel();
          _subscriptions.remove(device.address);

          // Notify connection lost
          if (onConnectionLost != null) {
            onConnectionLost!(device.address);
          }

          // Try to reconnect after a delay
          Future.delayed(BluetoothTimerConfig.reconnectAfterDisconnectDelay,
              () {
            _connectToPeer(device);
          });
        },
        onError: (error) {
          debugPrint('Bluetooth connection error: ${device.address} - $error');
        },
      );

      if (subscription != null) {
        _subscriptions[device.address] = subscription;
      }
    } catch (e) {
      debugPrint('Error connecting to ${device.address}: $e');
      _connectingDevices.remove(device.address);
    }
  }

  void _startReconnectionTimer() {
    _reconnectTimer = Timer.periodic(BluetoothTimerConfig.reconnectPollInterval,
        (timer) async {
      debugPrint('Checking Bluetooth connections...');
      await _connectToBondedDevices();
    });
  }

  void _handleIncomingData(String address, Uint8List data) {
    try {
      debugPrint('Bluetooth received ${data.length} bytes from $address');
      final message = TransportMessage(
        fromPeerId: address,
        fromAddress: address,
        data: data,
      );
      _messageController.add(message);
    } catch (e) {
      debugPrint('Error handling incoming Bluetooth data: $e');
    }
  }

  @override
  Future<bool> sendMessage(String peerId, Uint8List data) async {
    debugPrint('BluetoothTransport.sendMessage to $peerId');

    // Fail fast for non-Bluetooth transport IDs so MultiTransport can
    // immediately fall back to WiFi instead of waiting on Bluetooth logic.
    if (!_bluetoothMacPattern.hasMatch(peerId)) {
      debugPrint('  Not a Bluetooth MAC address, skipping Bluetooth send');
      return false;
    }

    final connection = _connections[peerId];
    if (connection == null || !connection.isConnected) {
      debugPrint('  No active connection to $peerId');
      debugPrint('  Available connections: ${_connections.keys.toList()}');

      // Fallback behavior: attempt reconnect on Bluetooth path.
      final bondedDevices = await _bluetooth.bondedDevices;
      if (bondedDevices != null) {
        BluetoothDevice? device;
        try {
          device = bondedDevices.firstWhere(
            (d) => d.address == peerId,
          );
        } catch (e) {
          debugPrint('  Device not found in bonded devices');
          device = null;
        }

        if (device != null) {
          debugPrint('  Attempting to reconnect...');
          await _connectToPeer(device);

          // Check again after reconnection attempt
          final newConnection = _connections[peerId];
          if (newConnection != null && newConnection.isConnected) {
            debugPrint('  Reconnected! Sending message...');
            try {
              newConnection.output.add(data);
              debugPrint('  Data sent successfully');
              return true;
            } catch (e) {
              debugPrint('  Error sending after reconnect: $e');
              return false;
            }
          }
        }
      }

      return false;
    }

    try {
      debugPrint('  Sending ${data.length} bytes...');
      connection.output.add(data);
      debugPrint('  Data sent successfully');
      return true;
    } catch (e) {
      debugPrint('  Error sending: $e');
      _connections.remove(peerId);
      return false;
    }
  }

  @override
  List<String> getConnectedPeerIds() {
    return _connections.keys.where((peerId) {
      final connection = _connections[peerId];
      return connection != null && connection.isConnected;
    }).toList();
  }

  @override
  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {
    // Bluetooth transport writes directly to the socket output stream and
    // does not maintain an internal outbound queue to flush.
  }

  @override
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    for (final connection in _connections.values) {
      await connection.close();
    }
    await _messageController.close();
  }
}
