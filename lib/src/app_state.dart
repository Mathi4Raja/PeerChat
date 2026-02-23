import 'package:flutter/material.dart';
import 'package:sodium/sodium.dart';
import 'package:sodium_libs/sodium_libs.dart' hide SodiumInit;
import 'package:sodium_libs/sodium_libs.dart' as sodium_libs show SodiumInit;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'models/peer.dart';
import 'services/db_service.dart';
import 'services/discovery_service.dart';
import 'services/mesh_router_service.dart';
import 'services/crypto_service.dart';
import 'services/deduplication_cache.dart';
import 'services/signature_verifier.dart';
import 'services/message_queue.dart';
import 'services/transport_service.dart';
import 'services/delivery_ack_handler.dart';
import 'services/connection_manager.dart';
import 'services/file_transfer_service.dart';
import 'services/route_manager.dart';
import 'services/message_manager.dart';
import 'utils/name_generator.dart';

class AppState extends ChangeNotifier {
  late final Sodium _sodium;
  final DBService _db = DBService();
  final DiscoveryService _discovery = DiscoveryService();
  late final MeshRouterService meshRouter;
  Timer? _peerRefreshTimer;

  List<Peer> peers = [];
  Map<String, int> unreadCounts = {};
  
  // Expose database service for manual peer addition
  DBService get db => _db;
  
  // Get peers with PeerChat app installed (discovered via mDNS)
  List<Peer> get peersWithApp {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fiveMinutesAgo = now - (5 * 60 * 1000); // 5 minutes
    
    // Only show peers seen in the last 5 minutes, excluding self
    return peers.where((p) => p.hasApp && p.lastSeen > fiveMinutesAgo && p.id != publicKey).toList();
  }
  
  // Get peers without app (Bluetooth-only discovery)
  List<Peer> get peersWithoutApp {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fiveMinutesAgo = now - (5 * 60 * 1000); // 5 minutes
    
    // Only show peers seen in the last 5 minutes, excluding self
    return peers.where((p) => !p.hasApp && p.lastSeen > fiveMinutesAgo && p.id != publicKey).toList();
  }
  
  // Get all active peers (seen in last 5 minutes, excluding self)
  List<Peer> get activePeers {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fiveMinutesAgo = now - (5 * 60 * 1000);
    final active = peers.where((p) => p.lastSeen > fiveMinutesAgo && p.id != publicKey).toList();
    debugPrint('AppState.activePeers: ${active.length} of ${peers.length} peers are active');
    return active;
  }
  
  // Get connected peers (those we have active connections with)
  List<Peer> get connectedPeers {
    final connectedIds = meshRouter.getConnectedPeerIds();
    debugPrint('AppState.connectedPeers: ${connectedIds.length} connected IDs from MeshRouter');
    final connected = activePeers.where((p) => connectedIds.contains(p.id)).toList();
    debugPrint('AppState.connectedPeers: ${connected.length} peers match connected IDs');
    return connected;
  }
  
  // Get discovered but not connected peers
  List<Peer> get discoveredPeers {
    final connectedIds = meshRouter.getConnectedPeerIds();
    return activePeers.where((p) => !connectedIds.contains(p.id)).toList();
  }

  String? get publicKey => meshRouter.localPeerId;
  
  // Get human-readable name from public key (Signing Key)
  String get displayName {
    final key = publicKey;
    if (key == null) return 'Generating...';
    return NameGenerator.generateName(key);
  }
  
  // Get short name (without number)
  String get shortName {
    final key = publicKey;
    if (key == null) return 'Unknown';
    return NameGenerator.generateShortName(key);
  }
  
  // Get initials
  String get initials {
    final key = publicKey;
    if (key == null) return 'U';
    return NameGenerator.generateInitials(key);
  }

  Future<void> init() async {
    try {
      debugPrint('AppState.init: Initializing Sodium...');
      _sodium = await sodium_libs.SodiumInit.init();
      
      debugPrint('AppState.init: Opening Database...');
      peers = await _db.allPeers();
      
      debugPrint('AppState.init: Composing P2P Services...');
      final cryptoService = CryptoService(_sodium);
      final deduplicationCache = DeduplicationCache(_db);
      final signatureVerifier = SignatureVerifier(cryptoService, _db);
      final messageQueue = MessageQueue(_db);
      final transportService = MultiTransportService();
      final deliveryAckHandler = DeliveryAckHandler(_db, cryptoService);
      final connectionManager = ConnectionManager(_db, cryptoService);
      final fileTransferService = FileTransferService(_db, transportService, connectionManager);

      // RouteManager needs a transport callback
      final routeManager = RouteManager(
        _db,
        signatureVerifier,
        cryptoService,
        (peerId, data) async {
          final transportId = connectionManager.getTransportId(peerId);
          return transportId != null ? await transportService.sendMessage(transportId, data) : false;
        },
      );

      // MessageManager needs a transport callback for relay/ACKs
      final messageManager = MessageManager(
        cryptoService,
        routeManager,
        messageQueue,
        deduplicationCache,
        signatureVerifier,
        deliveryAckHandler,
        (peerId, data) async {
          final transportId = connectionManager.getTransportId(peerId);
          return transportId != null ? await transportService.sendMessage(transportId, data) : false;
        },
      );

      debugPrint('AppState.init: Initializing MeshRouter...');
      // Initialize combined mesh router service
      meshRouter = MeshRouterService(
        sodium: _sodium,
        db: _db,
        discovery: _discovery,
        cryptoService: cryptoService,
        deduplicationCache: deduplicationCache,
        signatureVerifier: signatureVerifier,
        messageQueue: messageQueue,
        routeManager: routeManager,
        deliveryAckHandler: deliveryAckHandler,
        messageManager: messageManager,
        transportService: transportService,
        connectionManager: connectionManager,
        fileTransferService: fileTransferService,
      );
      
      await meshRouter.init();
      await fileTransferService.init(); // Initialize file transfer recovery last
      
      debugPrint('AppState.init: Setting local name...');
      // Update WiFi Direct advertising with generated name
      meshRouter.updateLocalName(displayName);
      
      // Listen to mesh router changes and reload peers
      meshRouter.addListener(() async {
        debugPrint('AppState: MeshRouter changed, reloading peers...');
        final oldCount = peers.length;
        peers = await _db.allPeers();
        debugPrint('AppState: Reloaded ${peers.length} peers (was $oldCount)');
        
        // Log active peers with their lastSeen timestamps
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final peer in peers) {
          final ageSeconds = ((now - peer.lastSeen) / 1000).round();
          final shortId = peer.id.length > 8 ? peer.id.substring(0, 8) : peer.id;
          debugPrint('  - ${peer.displayName} ($shortId): ${ageSeconds}s ago');
        }
        
        await refreshUnreadCounts();
        notifyListeners();
        debugPrint('AppState: notifyListeners() called');
      });
      
      // Listen for new messages to update unread counts
      meshRouter.onMessageReceived.listen((message) async {
        await refreshUnreadCounts();
      });
      
      // start discovery (use default port 9000 for now)
      _discovery.onPeerFound.listen((p) async {
        await _db.upsertPeer(p);
        peers = await _db.allPeers();
        notifyListeners();
      });
      
      debugPrint('AppState.init: Starting Discovery...');
      try {
        await _discovery.start(publicKey ?? 'unknown', 9000, name: displayName);
      } catch (e) {
        debugPrint('AppState.init: Discovery failed (non-fatal): $e');
      }
      
      // Start periodic peer list refresh (every 10 seconds)
      _startPeerRefresh();
      debugPrint('AppState.init: Complete!');
    } catch (e, stack) {
      debugPrint('AppState.init: CRITICAL FAILURE: $e');
      debugPrint(stack.toString());
      rethrow;
    }
  }
  
  void _startPeerRefresh() {
    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      debugPrint('AppState: Periodic peer refresh (10s timer)');
      final oldCount = peers.length;
      peers = await _db.allPeers();
      debugPrint('AppState: Timer reloaded ${peers.length} peers (was $oldCount)');
      
      // Log active peers count
      final now = DateTime.now().millisecondsSinceEpoch;
      final fiveMinutesAgo = now - (5 * 60 * 1000);
      final activeCount = peers.where((p) => p.lastSeen > fiveMinutesAgo && p.id != publicKey).length;
      debugPrint('AppState: $activeCount active peers (seen in last 5 min)');
      
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _peerRefreshTimer?.cancel();
    super.dispose();
  }

  // Refresh peer discovery (including WiFi Direct)
  Future<void> refreshDiscovery() async {
    try {
      debugPrint('Refreshing discovery services...');
      
      // Restart mDNS discovery service
      await _discovery.stop();
      await _discovery.start(publicKey ?? 'unknown', 9000, name: displayName);
      
      // Restart WiFi Direct advertising and discovery
      await meshRouter.restartWiFiDirect();
      
      // Reload peers from database
      peers = await _db.allPeers();
      notifyListeners();
      
      debugPrint('Discovery services restarted successfully');
    } catch (e) {
      debugPrint('Error refreshing discovery: $e');
      // Ignore errors, discovery might already be stopped
    }
  }
  Future<void> reloadPeers() async {
    peers = await _db.allPeers();
    await refreshUnreadCounts();
    notifyListeners();
  }

  Future<void> refreshUnreadCounts() async {
    unreadCounts = await _db.getUnreadMessageCounts();
    notifyListeners();
  }

  Future<void> markChatAsRead(String peerId) async {
    // Get list of unread message IDs before marking them as read locally
    final unreadIds = await _db.getUnreadMessageIds(peerId);
    
    // Mark as read in local database
    await _db.markMessagesAsRead(peerId);
    await refreshUnreadCounts();

    // Send read receipts to the sender
    if (unreadIds.isNotEmpty) {
      await meshRouter.sendReadReceipt(
        recipientPeerId: peerId,
        messageIds: unreadIds,
      );
    }
  }
}

// Helper functions (small utilities)

Uint8List base64Decode(String s) => Uint8List.fromList(base64.decode(s));
String base64Encode(Uint8List b) => base64.encode(b);
