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
    return peers.where((p) => p.lastSeen > fiveMinutesAgo && p.id != publicKey).toList();
  }
  
  // Get connected peers (those we have active connections with)
  List<Peer> get connectedPeers {
    final connectedIds = meshRouter.getConnectedPeerIds();
    return activePeers.where((p) => connectedIds.contains(p.id)).toList();
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
      
      debugPrint('AppState.init: Initializing MeshRouter...');
      // Initialize mesh router service
      meshRouter = MeshRouterService(_sodium, _db, _discovery);
      await meshRouter.init();
      
      debugPrint('AppState.init: Setting local name...');
      // Update WiFi Direct advertising with generated name
      meshRouter.updateLocalName(displayName);
      
      // Listen to mesh router changes and reload peers
      meshRouter.addListener(() async {
        // Reload peers from database when mesh router state changes
        peers = await _db.allPeers();
        await refreshUnreadCounts();
        notifyListeners();
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
    _peerRefreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      // Trigger UI update to refresh active peer list
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _peerRefreshTimer?.cancel();
    super.dispose();
  }

  // Refresh peer discovery
  Future<void> refreshDiscovery() async {
    try {
      // Restart discovery service
      await _discovery.stop();
      await _discovery.start(publicKey ?? 'unknown', 9000, name: displayName);
      
      // Reload peers from database
      peers = await _db.allPeers();
      notifyListeners();
    } catch (e) {
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
