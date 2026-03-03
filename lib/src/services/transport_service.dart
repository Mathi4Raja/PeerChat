import 'dart:async';
import 'package:flutter/foundation.dart';

// Abstract transport interface
abstract class TransportService {
  Stream<TransportMessage> get onMessageReceived;
  Future<void> init();
  Future<bool> sendMessage(String peerId, Uint8List data);
  List<String> getConnectedPeerIds(); // Get list of connected peer IDs
  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {}
  Future<void> dispose();
}

class TransportMessage {
  final String fromPeerId;
  final String fromAddress;
  final Uint8List data;

  TransportMessage({
    required this.fromPeerId,
    required this.fromAddress,
    required this.data,
  });
}

// Multi-transport coordinator
class MultiTransportService extends ChangeNotifier {
  final List<TransportService> _transports = [];
  final StreamController<TransportMessage> _messageController =
      StreamController.broadcast();

  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  void addTransport(TransportService transport) {
    _transports.add(transport);
    transport.onMessageReceived.listen((message) {
      _messageController.add(message);
    });
  }

  Future<void> init() async {
    for (final transport in _transports) {
      try {
        await transport.init();
      } catch (e) {
        debugPrint('Error initializing transport: $e');
      }
    }
  }

  Future<bool> sendMessage(String peerId, Uint8List data) async {
    debugPrint('=== TRANSPORT SEND ===');
    debugPrint('Target peer: $peerId');
    debugPrint('Data size: ${data.length} bytes');
    debugPrint('Trying ${_transports.length} transports...');

    // Try each transport until one succeeds
    for (int i = 0; i < _transports.length; i++) {
      final transport = _transports[i];
      try {
        debugPrint('  Transport ${i + 1}: ${transport.runtimeType}');
        final success = await transport.sendMessage(peerId, data);
        if (success) {
          debugPrint('  ✓ SUCCESS via ${transport.runtimeType}');
          return true;
        } else {
          debugPrint('  ✗ FAILED via ${transport.runtimeType}');
        }
      } catch (e) {
        debugPrint('  ✗ ERROR via ${transport.runtimeType}: $e');
      }
    }

    debugPrint('All transports failed');
    return false;
  }

  List<String> getConnectedPeerIds() {
    final connectedIds = <String>{};
    for (final transport in _transports) {
      try {
        connectedIds.addAll(transport.getConnectedPeerIds());
      } catch (e) {
        debugPrint('Error getting connected peers from transport: $e');
      }
    }
    return connectedIds.toList();
  }

  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {
    for (final transport in _transports) {
      try {
        transport.clearPendingForPeer(peerId, bulkOnly: bulkOnly);
      } catch (e) {
        debugPrint(
            'Error clearing pending frames for $peerId on ${transport.runtimeType}: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (final transport in _transports) {
      await transport.dispose();
    }
    await _messageController.close();
    super.dispose();
  }
}
