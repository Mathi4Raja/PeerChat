import 'dart:async';
import 'package:flutter/foundation.dart';

// Abstract transport interface
abstract class TransportService {
  Stream<TransportMessage> get onMessageReceived;
  Stream<FileTransferProgressEvent> get onFileProgress;
  Future<void> init();
  Future<bool> sendMessage(String peerId, Uint8List data,
      {bool isControl = false});
  Future<bool> sendFile(String peerId, String filePath, String fileId);
  List<String> getConnectedPeerIds(); // Get list of connected peer IDs
  void clearPendingForPeer(String peerId, {bool bulkOnly = false}) {}
  void updatePeerMapping(String transportId, String cryptoPeerId) {}
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

abstract class BaseTransport implements TransportService {
  final StreamController<TransportMessage> _messageController =
      StreamController<TransportMessage>.broadcast();
  @override
  Stream<TransportMessage> get onMessageReceived => _messageController.stream;

  final StreamController<FileTransferProgressEvent> _fileProgressController =
      StreamController<FileTransferProgressEvent>.broadcast();
  @override
  Stream<FileTransferProgressEvent> get onFileProgress =>
      _fileProgressController.stream;

  void Function(String transportId)? onConnectionEstablished;
  void Function(String transportId)? onConnectionLost;

  final Map<String, bool> _activeConnections = {};
  final Map<String, List<Uint8List>> _pendingQueues = {};

  bool isConnected(String transportId) =>
      _activeConnections[transportId] ?? false;

  @protected
  void notifyMessageReceived(TransportMessage message) {
    _messageController.add(message);
  }

  @protected
  void notifyFileProgress(FileTransferProgressEvent event) {
    _fileProgressController.add(event);
  }

  @protected
  void setConnectionState(String transportId, bool connected) {
    final wasConnected = _activeConnections[transportId] ?? false;
    _activeConnections[transportId] = connected;

    if (connected && !wasConnected) {
      onConnectionEstablished?.call(transportId);
      _flushQueue(transportId);
    } else if (!connected && wasConnected) {
      onConnectionLost?.call(transportId);
    }
  }

  @protected
  void enqueueMessage(String transportId, Uint8List data) {
    _pendingQueues.putIfAbsent(transportId, () => []).add(data);
    debugPrint(
        "Message queued for $transportId (total: ${_pendingQueues[transportId]!.length})");
  }

  Future<void> _flushQueue(String transportId) async {
    final queue = _pendingQueues[transportId];
    if (queue == null || queue.isEmpty) return;

    debugPrint("Flushing ${queue.length} messages for $transportId");
    final toSend = List<Uint8List>.from(queue);
    queue.clear();

    for (final data in toSend) {
      final success = await sendMessage(transportId, data);
      if (!success) {
        queue.insert(0, data);
        break;
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _messageController.close();
    await _fileProgressController.close();
  }
}

class FileTransferProgressEvent {
  final String peerId;
  final String fileId;
  final double progress;
  final bool isCompleted;
  final String? localPath;

  FileTransferProgressEvent({
    required this.peerId,
    required this.fileId,
    required this.progress,
    required this.isCompleted,
    this.localPath,
  });
}

// Multi-transport coordinator
class MultiTransportService extends ChangeNotifier {
  final List<TransportService> _transports = [];
  final StreamController<TransportMessage> _messageController =
      StreamController.broadcast();
  final StreamController<FileTransferProgressEvent> _fileProgressController =
      StreamController.broadcast();

  Stream<TransportMessage> get onMessageReceived => _messageController.stream;
  Stream<FileTransferProgressEvent> get onFileProgress =>
      _fileProgressController.stream;

  void addTransport(TransportService transport) {
    _transports.add(transport);
    transport.onMessageReceived.listen((message) {
      _messageController.add(message);
    });
    transport.onFileProgress.listen((event) {
      _fileProgressController.add(event);
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

  Future<bool> sendMessage(String peerId, Uint8List data,
      {bool isControl = false}) async {
    debugPrint('=== TRANSPORT SEND ===');
    debugPrint('Target peer: $peerId');
    debugPrint('Data size: ${data.length} bytes');
    debugPrint('Trying ${_transports.length} transports...');

    // Try each transport until one succeeds
    for (int i = 0; i < _transports.length; i++) {
      final transport = _transports[i];
      try {
        debugPrint('  Transport ${i + 1}: ${transport.runtimeType}');
        final success =
            await transport.sendMessage(peerId, data, isControl: isControl);
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

  Future<bool> sendFile(String peerId, String filePath, String fileId) async {
    debugPrint('=== TRANSPORT SEND FILE ===');
    debugPrint('Target peer: $peerId');
    debugPrint('File: $filePath');

    for (final transport in _transports) {
      try {
        final success = await transport.sendFile(peerId, filePath, fileId);
        if (success) return true;
      } catch (e) {
        debugPrint('Error sending file via ${transport.runtimeType}: $e');
      }
    }
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

  void updatePeerMapping(String transportId, String cryptoPeerId) {
    for (final transport in _transports) {
      try {
        transport.updatePeerMapping(transportId, cryptoPeerId);
      } catch (e) {
        debugPrint('Error updating peer mapping on ${transport.runtimeType}: $e');
      }
    }
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
