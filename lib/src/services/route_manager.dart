import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'db_service.dart';
import 'signature_verifier.dart';
import 'crypto_service.dart';
import '../models/route.dart';
import '../models/route_discovery.dart';
import '../models/peer.dart';
import '../models/mesh_message.dart';
import '../config/timer_config.dart';
import '../config/limits_config.dart';
import 'package:uuid/uuid.dart';

class RouteManager {
  final DBService _db;
  final SignatureVerifier _signatureVerifier;
  final CryptoService _cryptoService;
  final Future<bool> Function(String peerId, Uint8List data)
      sendTransportMessage;
  final List<String> Function() connectedPeerIdsProvider;

  final Map<String, Completer<bool>> _pendingDiscoveries = {};
  final Map<String, int> _discoveryAttempts = {};
  final _uuid = const Uuid();

  final StreamController<String> _routeUpdateController =
      StreamController<String>.broadcast();
  Stream<String> get onRouteFound => _routeUpdateController.stream;
  Stream<String> get onRouteUpdated => _routeUpdateController.stream;

  RouteManager(
    this._db,
    this._signatureVerifier,
    this._cryptoService,
    this.sendTransportMessage,
    this.connectedPeerIdsProvider,
  );

  // Find next hop for a destination
  Future<String?> getNextHop(String destinationPeerId) async {
    final database = await _db.db;

    // Query routing table for best route
    final results = await database.query(
      'routes',
      where: 'destination_peer_id = ?',
      whereArgs: [destinationPeerId],
    );

    if (results.isEmpty) {
      return null;
    }

    // If multiple routes exist, select best one based on score
    final routes = results.map((map) => Route.fromMap(map)).toList();
    routes.sort((a, b) => b.preferenceScore.compareTo(a.preferenceScore));

    return routes.first.nextHopPeerId;
  }

  // Get all routes from routing table (for debug UI)
  Future<List<Route>> getAllRoutes() async {
    final database = await _db.db;
    final results =
        await database.query('routes', orderBy: 'last_updated_timestamp DESC');
    return results.map((map) => Route.fromMap(map)).toList();
  }

  // Add or update a route
  Future<void> addRoute(Route route) async {
    final database = await _db.db;

    // Check for existing route
    final existing = await database.query(
      'routes',
      where: 'destination_peer_id = ?',
      whereArgs: [route.destinationPeerId],
    );

    bool shouldUpdate = true;
    if (existing.isNotEmpty) {
      final existingRoute = Route.fromMap(existing.first);
      // Only replace if new route is better or equally good (lower or equal hop count)
      if (route.hopCount > existingRoute.hopCount) {
        // New route is worse - just update timestamp of the existing one
        await database.update(
          'routes',
          {
            'last_updated_timestamp': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'destination_peer_id = ?',
          whereArgs: [route.destinationPeerId],
        );
        shouldUpdate = false;
      }
    }

    if (shouldUpdate) {
      await database.insert(
        'routes',
        route.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint(
          'Route added/updated: ${route.destinationPeerId} via ${route.nextHopPeerId} (${route.hopCount} hops)');
      _routeUpdateController.add(route.destinationPeerId);
    }
  }

  // Initiate route discovery for a destination
  Future<bool> discoverRoute(String destinationPeerId) async {
    // Check if discovery already in progress
    if (_pendingDiscoveries.containsKey(destinationPeerId)) {
      return await _pendingDiscoveries[destinationPeerId]!.future;
    }

    final completer = Completer<bool>();
    _pendingDiscoveries[destinationPeerId] = completer;

    // Get attempt count for exponential backoff
    final attempts = _discoveryAttempts[destinationPeerId] ?? 0;
    if (attempts >= 5) {
      debugPrint('Max discovery attempts (5) reached for $destinationPeerId.');
      _pendingDiscoveries.remove(destinationPeerId);
      return false;
    }
    _discoveryAttempts[destinationPeerId] = attempts + 1;

    // Create route request
    final requestId = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final request = RouteRequest(
      requestId: requestId,
      requestorPeerId: _cryptoService.localPeerId,
      targetPeerId: destinationPeerId,
      ttl: MessageLimits.routeControlTtl,
      timestamp: timestamp,
      signature: _cryptoService.signMessage(
        RouteRequest(
          requestId: requestId,
          requestorPeerId: _cryptoService.localPeerId,
          targetPeerId: destinationPeerId,
          ttl: MessageLimits.routeControlTtl,
          timestamp: timestamp,
          signature: Uint8List(0),
        ).toBytesForSigning(),
      ),
    );

    // Broadcast only to currently connected peers to avoid O(N all-peers) churn.
    final peers = connectedPeerIdsProvider().toSet().toList();
    if (peers.isEmpty) {
      completer.complete(false);
      _pendingDiscoveries.remove(destinationPeerId);
      return false;
    }

    // Convert request to MeshMessage for transport
    // Note: We need to wrap RouteRequest in a MeshMessage structure or send as raw bytes depending on protocol
    // Looking at MeshMessage, it has a type for routeRequest.
    // We should construct a MeshMessage to carry this payload.

    // Actually, RouteRequest has its own bytes. Let's send those.
    // The receiver needs to know it's a route request.
    // Usually we wrap everything in MeshMessage.
    // Let's create a MeshMessage wrapper for the route request.

    final meshMessage = MeshMessage(
      messageId: _uuid.v4(),
      type: MessageType.routeRequest,
      senderPeerId: _cryptoService.localPeerId,
      recipientPeerId: destinationPeerId, // Target of the discovery
      ttl: MessageLimits.routeControlTtl,
      hopCount: 0,
      priority: MessagePriority.high,
      timestamp: timestamp,
      signature: Uint8List(
          0), // Signature logic for wrapper might be redundant if inner is signed
      encryptedContent: request.toBytes(), // Payload is the request
    );

    // We haven't signed the wrapper properly here (it needs to be signed).
    // A better approach might be to send the payload directly if Transport handles packaging,
    // BUT MeshRouterService.receiveMessage expects MeshMessage.fromBytes.
    // So we MUST send a MeshMessage.

    // Sign the wrapper
    final wrapperSignature =
        _cryptoService.signMessage(meshMessage.toBytesForSigning());
    final signedWrapper = MeshMessage(
      messageId: meshMessage.messageId,
      type: MessageType.routeRequest,
      senderPeerId: meshMessage.senderPeerId,
      recipientPeerId: meshMessage.recipientPeerId,
      ttl: meshMessage.ttl,
      hopCount: meshMessage.hopCount,
      priority: meshMessage.priority,
      timestamp: meshMessage.timestamp,
      encryptedContent: meshMessage.encryptedContent,
      signature: wrapperSignature,
    );

    final messageBytes = signedWrapper.toBytes();

    for (final peerId in peers) {
      await sendTransportMessage(peerId, messageBytes);
    }

    // Set timeout for discovery
    final timeoutDuration = Duration(seconds: _calculateBackoff(attempts));
    Timer(timeoutDuration, () {
      if (!completer.isCompleted) {
        completer.complete(false);
        _pendingDiscoveries.remove(destinationPeerId);
      }
    });

    return completer.future;
  }

  // Calculate exponential backoff (1s, 2s, 4s, 8s, max 8s)
  int _calculateBackoff(int attempts) {
    final backoff =
        1 << attempts.clamp(0, RouteTimerConfig.discoveryBackoffMaxExponent);
    return backoff.clamp(
      RouteTimerConfig.discoveryBackoffMinSeconds,
      RouteTimerConfig.discoveryBackoffMaxSeconds,
    );
  }

  // Update routing table when peer connectivity changes
  Future<void> onPeerConnected(Peer peer) async {
    // Add single-hop route to newly connected peer.
    final route = Route(
      destinationPeerId: peer.id,
      nextHopPeerId: peer.id,
      hopCount: 1,
      lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
      lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
      successCount: 0,
      failureCount: 0,
    );

    await addRoute(route);
  }

  Future<void> onPeerDisconnected(String peerId) async {
    await removeRoutesThrough(peerId);
  }

  // Remove routes through a specific peer
  Future<void> removeRoutesThrough(String peerId) async {
    final database = await _db.db;
    await database.delete(
      'routes',
      where: 'next_hop_peer_id = ?',
      whereArgs: [peerId],
    );
  }

  // Mark route as failed
  Future<void> markRouteFailed(String destinationPeerId, String nextHop) async {
    final database = await _db.db;

    final results = await database.query(
      'routes',
      where: 'destination_peer_id = ? AND next_hop_peer_id = ?',
      whereArgs: [destinationPeerId, nextHop],
    );

    if (results.isEmpty) return;

    final route = Route.fromMap(results.first);
    final updatedRoute = route.copyWith(
      failureCount: route.failureCount + 1,
      lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
    );

    await database.update(
      'routes',
      updatedRoute.toMap(),
      where: 'destination_peer_id = ? AND next_hop_peer_id = ?',
      whereArgs: [destinationPeerId, nextHop],
    );
  }

  // Mark route as successful
  Future<void> markRouteSuccess(
      String destinationPeerId, String nextHop) async {
    final database = await _db.db;

    final results = await database.query(
      'routes',
      where: 'destination_peer_id = ? AND next_hop_peer_id = ?',
      whereArgs: [destinationPeerId, nextHop],
    );

    if (results.isEmpty) return;

    final route = Route.fromMap(results.first);
    final now = DateTime.now().millisecondsSinceEpoch;
    final updatedRoute = route.copyWith(
      successCount: route.successCount + 1,
      lastUsedTimestamp: now,
      lastUpdatedTimestamp: now,
    );

    await database.update(
      'routes',
      updatedRoute.toMap(),
      where: 'destination_peer_id = ? AND next_hop_peer_id = ?',
      whereArgs: [destinationPeerId, nextHop],
    );
  }

  // Expire stale routes (called periodically)
  Future<void> expireStaleRoutes() async {
    final database = await _db.db;
    final cutoffTimestamp = DateTime.now()
        .subtract(RouteTimerConfig.staleRouteAge)
        .millisecondsSinceEpoch;

    // Remove stale routes (not used in 30 minutes)
    await database.delete(
      'routes',
      where: 'last_used_timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );

    // Route failure-rate pruning: remove routes with >70% failure rate
    // Only prune routes that have been tried at least 5 times (avoid noise)
    await database.rawDelete('''
      DELETE FROM routes
      WHERE (success_count + failure_count) >= ?
        AND CAST(failure_count AS REAL) / (success_count + failure_count) > ?
    ''', [
      RouteLimits.failurePruneMinSamples,
      RouteLimits.failurePruneThreshold,
    ]);
  }

  // Process route discovery request
  Future<void> handleRouteRequest(
      RouteRequest request, String fromPeerAddress) async {
    // Verify signature
    final isValid =
        await _signatureVerifier.verifyRouteRequestSignature(request);
    if (!isValid) {
      await _signatureVerifier.recordInvalidSignature(request.requestorPeerId);
      return;
    }

    // Check if we are the target
    if (request.targetPeerId == _cryptoService.localPeerId) {
      // Send route response back
      final response = RouteResponse(
        requestId: request.requestId,
        responderPeerId: _cryptoService.localPeerId,
        targetPeerId: request.targetPeerId,
        hopCount: 0,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        signature: _cryptoService.signMessage(
          RouteResponse(
            requestId: request.requestId,
            responderPeerId: _cryptoService.localPeerId,
            targetPeerId: request.targetPeerId,
            hopCount: 0,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            signature: Uint8List(0),
          ).toBytesForSigning(),
        ),
      );

      // Calculate next hop to requestor
      final nextHop = await getNextHop(request.requestorPeerId);
      if (nextHop != null) {
        // Wrap response in MeshMessage so receiver can parse it consistently.
        final wrapper = MeshMessage(
          messageId: _uuid.v4(),
          type: MessageType.routeResponse,
          senderPeerId: _cryptoService.localPeerId,
          recipientPeerId: request.requestorPeerId,
          ttl: MessageLimits.routeControlTtl,
          hopCount: 0,
          priority: MessagePriority.high,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          encryptedContent: response.toBytes(),
          signature: Uint8List(0),
        );
        final signedWrapper = wrapper.copyWithSignature(
          _cryptoService.signMessage(wrapper.toBytesForSigning()),
        );
        await sendTransportMessage(nextHop, signedWrapper.toBytes());
        debugPrint(
            'Sent route response to ${request.requestorPeerId} via $nextHop');
      } else {
        debugPrint(
            'Cannot send route response: No route to ${request.requestorPeerId}');
      }
      return;
    }

    // Check if we have a route to target
    final nextHop = await getNextHop(request.targetPeerId);
    if (nextHop != null && request.ttl > 0) {
      // Forward request with decremented TTL
      final forwardedRequest = RouteRequest(
        requestId: request.requestId,
        requestorPeerId: request.requestorPeerId,
        targetPeerId: request.targetPeerId,
        ttl: request.ttl - 1,
        timestamp: request.timestamp,
        signature: request.signature,
      );

      // Wrap forwarded request in MeshMessage so receiver parsing stays consistent.
      final wrapper = MeshMessage(
        messageId: _uuid.v4(),
        type: MessageType.routeRequest,
        senderPeerId: _cryptoService.localPeerId,
        recipientPeerId: request.targetPeerId,
        ttl: request.ttl - 1,
        hopCount: 0,
        priority: MessagePriority.high,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        encryptedContent: forwardedRequest.toBytes(),
        signature: Uint8List(0),
      );
      final signedWrapper = wrapper.copyWithSignature(
        _cryptoService.signMessage(wrapper.toBytesForSigning()),
      );

      // Forward to next hop via transport layer
      debugPrint(
          'Forwarding route request for ${request.targetPeerId} to $nextHop');
      await sendTransportMessage(nextHop, signedWrapper.toBytes());
    } else {
      debugPrint(
          'Dropping route request for ${request.targetPeerId}: No route or TTL expired');
    }
  }

  // Process route discovery response
  Future<void> handleRouteResponse(RouteResponse response) async {
    // Verify signature
    final isValid = await _signatureVerifier.verifyRouteSignature(response);
    if (!isValid) {
      await _signatureVerifier.recordInvalidSignature(response.responderPeerId);
      return;
    }

    // Add route to routing table
    final route = Route(
      destinationPeerId: response.targetPeerId,
      nextHopPeerId: response.responderPeerId,
      hopCount: response.hopCount + 1,
      lastUsedTimestamp: DateTime.now().millisecondsSinceEpoch,
      lastUpdatedTimestamp: DateTime.now().millisecondsSinceEpoch,
      successCount: 0,
      failureCount: 0,
    );

    await addRoute(route);

    // Complete pending discovery if exists
    if (_pendingDiscoveries.containsKey(response.targetPeerId)) {
      _pendingDiscoveries[response.targetPeerId]!.complete(true);
      _pendingDiscoveries.remove(response.targetPeerId);
      _discoveryAttempts.remove(response.targetPeerId);
    }
  }

  // Get routing statistics
  Future<Map<String, int>> getStats() async {
    final database = await _db.db;

    final totalRoutes = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM routes'),
        ) ??
        0;

    return {
      'total_routes': totalRoutes,
      'pending_discoveries': _pendingDiscoveries.length,
    };
  }

  void dispose() {
    _routeUpdateController.close();
  }
}
