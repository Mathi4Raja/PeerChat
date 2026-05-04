import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bluetooth_classic/bluetooth_classic.dart';
import 'package:bluetooth_classic/models/device.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/timer_config.dart';
import '../config/protocol_config.dart';
import 'transport_service.dart';

class BluetoothTransport extends BaseTransport {
  final BluetoothClassic _bluetooth = BluetoothClassic();
  final Map<String, StreamSubscription> _subscriptions = {};
  final Set<String> _connectingDevices =
      {}; // Track devices we're connecting to
  String? _connectedPeerId;
  Device? _connectedDevice;
  static final RegExp _bluetoothMacPattern =
      RegExp(r'^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$');

  Timer? _reconnectTimer;

  @override
  Future<void> init() async {
    try {
      // Request Bluetooth permissions
      await _requestPermissions();

      final permissionGranted = await _bluetooth.initPermissions();
      if (!permissionGranted) {
        debugPrint('Bluetooth permissions were not granted');
        return;
      }

      _startBluetoothEventListeners();

      // Connect to bonded devices only (more reliable)
      await _connectToBondedDevices();

      // Start periodic reconnection attempts
      _startReconnectionTimer();

      debugPrint('Bluetooth transport initialized');
    } catch (e) {
      debugPrint('Error initializing Bluetooth: $e');
    }
  }

  void _startBluetoothEventListeners() {
    _subscriptions['status'] ??= _bluetooth.onDeviceStatusChanged().listen(
      _handleConnectionStatus,
      onError: (error) {
        debugPrint('Bluetooth status stream error: $error');
      },
    );
    _subscriptions['data'] ??= _bluetooth.onDeviceDataReceived().listen(
      (data) {
        final peerId = _connectedPeerId;
        if (peerId == null) {
          debugPrint('Bluetooth data received without an active peer');
          return;
        }
        _handleIncomingData(peerId, data);
      },
      onError: (error) {
        debugPrint('Bluetooth data stream error: $error');
      },
    );
  }

  void _handleConnectionStatus(int status) {
    if (status != Device.disconnected) return;
    final disconnectedPeerId = _connectedPeerId;
    if (disconnectedPeerId == null) return;

    debugPrint('Bluetooth connection closed: $disconnectedPeerId');
    _connectedPeerId = null;
    final disconnectedDevice = _connectedDevice;
    _connectedDevice = null;
    onConnectionLost?.call(disconnectedPeerId);

    if (disconnectedDevice != null) {
      Future.delayed(BluetoothTimerConfig.reconnectAfterDisconnectDelay, () {
        _connectToPeer(disconnectedDevice);
      });
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
      final bondedDevices = await _bluetooth.getPairedDevices();

      if (bondedDevices.isEmpty) {
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

  Future<void> _connectToPeer(Device device) async {
    // Skip if already connected or connecting
    if (_connectedPeerId == device.address ||
        _connectingDevices.contains(device.address)) {
      return;
    }

    _connectingDevices.add(device.address);

    try {
      debugPrint(
          'Attempting Bluetooth connection to ${device.address} (${device.name})...');

      if (_connectedPeerId != null) {
        await _disconnectActivePeer();
      }

      final connected = await _bluetooth
          .connect(device.address, ProtocolConfig.bluetoothSerialServiceUuid)
          .timeout(
        BluetoothTimerConfig.connectTimeout,
        onTimeout: () {
          debugPrint('Bluetooth connection timeout: ${device.address}');
          return false;
        },
      );

      if (!connected) {
        debugPrint('Bluetooth connection failed for ${device.address}');
        _connectingDevices.remove(device.address);
        return;
      }

      _connectedPeerId = device.address;
      _connectedDevice = device;
      _connectingDevices.remove(device.address);
      debugPrint('✓ Bluetooth connected: ${device.address}');

      // Notify connection established
      setConnectionState(device.address, true);
    } catch (e) {
      debugPrint('Error connecting to ${device.address}: $e');
      _connectingDevices.remove(device.address);
    }
  }

  Future<void> _disconnectActivePeer() async {
    final peerId = _connectedPeerId;
    if (peerId == null) return;
    try {
      await _bluetooth.disconnect();
    } catch (e) {
      debugPrint('Bluetooth disconnect failed for $peerId: $e');
    } finally {
      _connectedPeerId = null;
      _connectedDevice = null;
      setConnectionState(peerId, false);
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
      notifyMessageReceived(TransportMessage(
        fromPeerId: address,
        fromAddress: address,
        data: data,
      ));
    } catch (e) {
      debugPrint('Error handling incoming Bluetooth data: $e');
    }
  }

  @override
  Future<bool> sendMessage(String peerId, Uint8List data,
      {bool isControl = false}) async {
    debugPrint('BluetoothTransport.sendMessage to $peerId');

    // Fail fast for non-Bluetooth transport IDs so MultiTransport can
    // immediately fall back to WiFi instead of waiting on Bluetooth logic.
    if (!_bluetoothMacPattern.hasMatch(peerId)) {
      debugPrint('  Not a Bluetooth MAC address, skipping Bluetooth send');
      return false;
    }

    if (_connectedPeerId != peerId) {
      debugPrint('  No active connection to $peerId');
      debugPrint('  Active Bluetooth peer: $_connectedPeerId');

      // Fallback behavior: attempt reconnect on Bluetooth path.
      final bondedDevices = await _bluetooth.getPairedDevices();
      Device? device;
      try {
        device = bondedDevices.firstWhere(
          (d) => d.address == peerId,
        );
      } catch (e) {
        debugPrint('  Device not found in bonded devices');
        device = null;
      }

      if (device == null) return false;

      debugPrint('  Attempting to reconnect...');
      await _connectToPeer(device);

      if (_connectedPeerId != peerId) return false;
    }

    try {
      debugPrint('  Sending ${data.length} bytes...');
      final sent = await _bluetooth.writeBytes(data);
      if (!sent) {
        debugPrint('  Bluetooth write returned false');
        return false;
      }
      debugPrint('  Data sent successfully');
      return true;
    } catch (e) {
      debugPrint('  Error sending: $e');
      if (_connectedPeerId == peerId) {
        _connectedPeerId = null;
        _connectedDevice = null;
      }
      return false;
    }
  }

  @override
  void updatePeerMapping(String transportId, String cryptoPeerId) {
    if (_connectedPeerId == transportId) {
      debugPrint('BluetoothTransport: Mapping $transportId to $cryptoPeerId');
    }
  }

  @override
  List<String> getConnectedPeerIds() {
    final peerId = _connectedPeerId;
    return peerId == null ? [] : [peerId];
  }

  @override
  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {
    // Bluetooth transport writes directly to the socket output stream and
    // does not maintain an internal outbound queue to flush.
  }

  @override
  Future<bool> sendFile(String peerId, String filePath, String fileId) async {
    debugPrint('BluetoothTransport.sendFile not implemented');
    return false;
  }

  @override
  Stream<FileTransferProgressEvent> get onFileProgress => const Stream.empty();

  @override
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    await _disconnectActivePeer();
    await super.dispose();
  }
}
