import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sodium/sodium.dart';
import 'package:sodium_libs/sodium_libs.dart' hide SodiumInit;
import 'package:sodium_libs/sodium_libs.dart' as sodium_libs show SodiumInit;
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'models/peer.dart';
import 'models/file_transfer.dart';
import 'models/runtime_profile.dart';
import 'config/timer_config.dart';
import 'config/network_config.dart';
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
import 'services/emergency_broadcast_service.dart';
import 'services/battery_status_service.dart';
import 'services/wifi_transport.dart';
import 'utils/name_generator.dart';

class AppState extends ChangeNotifier {
  late final Sodium _sodium;
  final DBService _db = DBService();
  final DiscoveryService _discovery = DiscoveryService();
  late final MeshRouterService meshRouter;
  late final FileTransferService fileTransferService;
  late final EmergencyBroadcastService emergencyBroadcastService;
  bool _hasEmergencyBroadcastService = false;
  Timer? _peerRefreshTimer;
  Timer? _batteryPollTimer;
  StreamSubscription<FileTransferSession>? _transferPolicySubscription;
  StreamSubscription<FileTransferSession>? _incomingTransferPolicySubscription;
  StreamSubscription<WiFiDiscoveryFailure>? _wifiDiscoveryFailureSubscription;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final BatteryStatusService _batteryStatusService = BatteryStatusService();
  static const String _runtimeProfileStorageKey = 'runtime_profile';
  static const String _lastNormalRuntimeProfileStorageKey =
      'last_normal_runtime_profile';
  RuntimeProfile _runtimeProfile = RuntimeProfile.normalDirect;
  RuntimeProfile _lastNormalRuntimeProfile = RuntimeProfile.normalDirect;
  bool _batteryLow = false;
  bool _isCharging = false;
  int _batteryLevel = 100;
  WiFiDiscoveryFailure? _pendingDiscoveryFailure;
  int _pendingDiscoveryFailureVersion = 0;

  List<Peer> peers = [];
  Map<String, int> unreadCounts = {};

  // Expose database service for manual peer addition
  DBService get db => _db;
  bool get isBatteryLow => _batteryLow;
  bool get isCharging => _isCharging;
  int get batteryLevel => _batteryLevel;
  RuntimeProfile get runtimeProfile => _runtimeProfile;
  RuntimeProfile get preferredNormalRuntimeProfile => _lastNormalRuntimeProfile;
  bool get allowsFileTransfers =>
      _runtimeProfile == RuntimeProfile.normalDirect;
  bool get forceMeshRouting => _runtimeProfile != RuntimeProfile.normalDirect;
  bool get isEmergencyBatteryProfile =>
      _runtimeProfile == RuntimeProfile.emergencyBattery;
  RuntimeProfile? peerRuntimeProfile(String peerId) =>
      meshRouter.getPeerRuntimeProfile(peerId);
  bool peerSupportsFileTransfer(
    String peerId, {
    bool defaultValue = false,
  }) =>
      meshRouter.peerSupportsFileTransfer(peerId, defaultValue: defaultValue);
  bool isDirectSessionWithPeer(String peerId) {
    final remote = peerRuntimeProfile(peerId);
    return _runtimeProfile == RuntimeProfile.normalDirect &&
        remote == RuntimeProfile.normalDirect &&
        meshRouter.getConnectedPeerIds().contains(peerId);
  }

  bool isMeshSessionWithPeer(String peerId) => !isDirectSessionWithPeer(peerId);

  bool canSendFileToPeer(String peerId) =>
      isDirectSessionWithPeer(peerId) &&
      peerSupportsFileTransfer(peerId, defaultValue: false);
  WiFiDiscoveryFailure? get pendingDiscoveryFailure => _pendingDiscoveryFailure;
  int get pendingDiscoveryFailureVersion => _pendingDiscoveryFailureVersion;

  // Get peers with PeerChat app installed (discovered via mDNS)
  List<Peer> get peersWithApp {
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeWindowStart =
        now - AppStateTimerConfig.activePeerWindow.inMilliseconds;

    // Only show peers seen in the last 5 minutes, excluding self
    return peers
        .where((p) =>
            p.hasApp && p.lastSeen > activeWindowStart && p.id != publicKey)
        .toList();
  }

  // Get peers without app (Bluetooth-only discovery)
  List<Peer> get peersWithoutApp {
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeWindowStart =
        now - AppStateTimerConfig.activePeerWindow.inMilliseconds;

    // Only show peers seen in the last 5 minutes, excluding self
    return peers
        .where((p) =>
            !p.hasApp && p.lastSeen > activeWindowStart && p.id != publicKey)
        .toList();
  }

  // Get all active peers (seen in last 5 minutes, excluding self)
  List<Peer> get activePeers {
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeWindowStart =
        now - AppStateTimerConfig.activePeerWindow.inMilliseconds;
    final active = peers
        .where((p) => p.lastSeen > activeWindowStart && p.id != publicKey)
        .toList();
    debugPrint(
        'AppState.activePeers: ${active.length} of ${peers.length} peers are active');
    return active;
  }

  // Get connected peers (those we have active connections with)
  List<Peer> get connectedPeers {
    final connectedIds = meshRouter.getConnectedPeerIds();
    debugPrint(
        'AppState.connectedPeers: ${connectedIds.length} connected IDs from MeshRouter');
    final connected =
        activePeers.where((p) => connectedIds.contains(p.id)).toList();
    debugPrint(
        'AppState.connectedPeers: ${connected.length} peers match connected IDs');
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
      _runtimeProfile = await _loadRuntimeProfile();
      _lastNormalRuntimeProfile = await _loadLastNormalRuntimeProfile();
      if (_runtimeProfile != RuntimeProfile.emergencyBattery) {
        _lastNormalRuntimeProfile = _runtimeProfile;
        await _persistLastNormalRuntimeProfile(_lastNormalRuntimeProfile);
      }

      debugPrint('AppState.init: Composing P2P Services...');
      final cryptoService = CryptoService(_sodium);
      final deduplicationCache = DeduplicationCache(_db);
      final signatureVerifier = SignatureVerifier(cryptoService, _db);
      final messageQueue = MessageQueue(_db);
      final transportService = MultiTransportService();
      final deliveryAckHandler = DeliveryAckHandler(_db, cryptoService);
      deliveryAckHandler.setSignatureVerifier(signatureVerifier);
      final connectionManager = ConnectionManager(_db, cryptoService);
      fileTransferService =
          FileTransferService(_db, transportService, connectionManager);
      emergencyBroadcastService = EmergencyBroadcastService(
        cryptoService: cryptoService,
        connectionManager: connectionManager,
        transportService: transportService,
        deduplicationCache: deduplicationCache,
        signatureVerifier: signatureVerifier,
        db: _db,
      );
      _hasEmergencyBroadcastService = true;

      // RouteManager needs a transport callback
      final routeManager = RouteManager(
        _db,
        signatureVerifier,
        cryptoService,
        (peerId, data) async {
          final transportId = connectionManager.getTransportId(peerId);
          return transportId != null
              ? await transportService.sendMessage(transportId, data)
              : false;
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
          return transportId != null
              ? await transportService.sendMessage(transportId, data)
              : false;
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
        emergencyBroadcastService: emergencyBroadcastService,
      );

      meshRouter.setRuntimeProfile(_runtimeProfile);
      await meshRouter.init();
      _wifiDiscoveryFailureSubscription =
          meshRouter.onWiFiDiscoveryFailure.listen(
        _handleWiFiDiscoveryFailure,
      );
      await fileTransferService
          .init(); // Initialize file transfer recovery last
      _transferPolicySubscription =
          fileTransferService.onTransferUpdate.listen((_) {
        _applyDiscoveryPolicy();
      });
      _incomingTransferPolicySubscription =
          fileTransferService.onIncomingRequest.listen((session) async {
        if (!allowsFileTransfers) {
          await fileTransferService.rejectTransfer(session.fileId);
        }
      });
      await _requestBatteryOptimizationExemption();
      await _startBatteryMonitoring();

      final cleanupStats = await clearStaleNetworkData(
        stalePeerAge: DatabaseTimerConfig.stalePeerAge,
        staleRouteAge: DatabaseTimerConfig.staleRouteAge,
        staleEndpointAge: DatabaseTimerConfig.staleEndpointAge,
      );
      debugPrint(
          'AppState.init: stale cleanup peers=${cleanupStats['removed_peers']} routes=${(cleanupStats['removed_routes_by_age'] ?? 0) + (cleanupStats['removed_routes_via_stale_peers'] ?? 0)} queue=${cleanupStats['removed_queue_via_stale_peers']} endpoints=${cleanupStats['removed_known_endpoints']}');

      debugPrint('AppState.init: Setting local name...');
      // Update WiFi Direct advertising with generated name
      meshRouter.updateLocalName(displayName);

      // Listen to mesh router changes and reload peers
      meshRouter.addListener(() async {
        debugPrint('AppState: MeshRouter changed, reloading peers...');
        final oldCount = peers.length;
        peers = await _db.allPeers();
        final now = DateTime.now().millisecondsSinceEpoch;
        final activeCount = peers
            .where((p) =>
                p.id != publicKey &&
                (now - p.lastSeen) <=
                    AppStateTimerConfig.activePeerWindow.inMilliseconds)
            .length;
        debugPrint(
            'AppState: Reloaded ${peers.length} peers (was $oldCount), active=$activeCount');

        await refreshUnreadCounts();
        notifyListeners();
        debugPrint('AppState: notifyListeners() called');
      });

      // Listen for new messages to update unread counts
      meshRouter.onMessageReceived.listen((message) async {
        await refreshUnreadCounts();
      });

      // Start discovery using configured local service port.
      _discovery.onPeerFound.listen((p) async {
        await _db.upsertPeer(p);
        peers = await _db.allPeers();
        notifyListeners();
      });

      debugPrint('AppState.init: Starting Discovery...');
      try {
        // Discovery can hang on some Android builds (mDNS socket/reusePort issues).
        // Do not block full app startup on this path.
        await _discovery
            .start(publicKey ?? 'unknown', NetworkConfig.discoveryPort,
                name: displayName)
            .timeout(
          AppStateTimerConfig.discoveryStartupTimeout,
          onTimeout: () {
            debugPrint(
                'AppState.init: Discovery startup timed out (continuing)');
          },
        );
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
    _peerRefreshTimer =
        Timer.periodic(AppStateTimerConfig.peerRefreshInterval, (timer) async {
      debugPrint(
          'AppState: Periodic peer refresh (${AppStateTimerConfig.peerRefreshInterval.inSeconds}s timer)');
      final oldCount = peers.length;
      peers = await _db.allPeers();
      debugPrint(
          'AppState: Timer reloaded ${peers.length} peers (was $oldCount)');

      // Log active peers count
      final now = DateTime.now().millisecondsSinceEpoch;
      final activeWindowStart =
          now - AppStateTimerConfig.activePeerWindow.inMilliseconds;
      final activeCount = peers
          .where((p) => p.lastSeen > activeWindowStart && p.id != publicKey)
          .length;
      debugPrint('AppState: $activeCount active peers (seen in last 5 min)');

      final connectedCount = meshRouter.getConnectedPeerIds().length;
      _applyDiscoveryPolicy(connectedPeerCount: connectedCount);

      notifyListeners();
    });
  }

  Future<void> _startBatteryMonitoring() async {
    await _refreshBatteryStatus();
    _batteryPollTimer?.cancel();
    _batteryPollTimer =
        Timer.periodic(AppStateTimerConfig.batteryPollInterval, (_) async {
      await _refreshBatteryStatus();
    });
  }

  Future<void> _refreshBatteryStatus() async {
    final status = await _batteryStatusService.getStatus();
    final changed = _batteryLevel != status.level ||
        _isCharging != status.isCharging ||
        _batteryLow != status.isLow;

    _batteryLevel = status.level;
    _isCharging = status.isCharging;
    _batteryLow = status.isLow;

    _applyDiscoveryPolicy();

    if (changed) {
      debugPrint(
          'Battery status: level=$_batteryLevel charging=$_isCharging low=$_batteryLow');
      notifyListeners();
    }
  }

  void _applyDiscoveryPolicy({int? connectedPeerCount}) {
    if (!(_hasEmergencyBroadcastService ||
        peers.isNotEmpty ||
        publicKey != null)) {
      return;
    }

    final activeConnectedCount =
        connectedPeerCount ?? meshRouter.getConnectedPeerIds().length;
    final hasActiveTransfer = fileTransferService.activeTransfers.any(
      (t) =>
          t.state == FileTransferState.transferring ||
          t.state == FileTransferState.pending ||
          t.state == FileTransferState.verifying,
    );

    _discovery.updateAdaptiveDiscoveryPolicy(
      connectedPeerCount: activeConnectedCount,
      fileTransferActive: hasActiveTransfer,
      batteryLow: _batteryLow,
      runtimeProfile: _runtimeProfile,
    );
  }

  Future<RuntimeProfile> _loadRuntimeProfile() async {
    try {
      final raw = await _secureStorage.read(key: _runtimeProfileStorageKey);
      return runtimeProfileFromStorage(raw);
    } catch (_) {
      return RuntimeProfile.normalDirect;
    }
  }

  Future<void> _persistRuntimeProfile(RuntimeProfile profile) async {
    try {
      await _secureStorage.write(
        key: _runtimeProfileStorageKey,
        value: profile.storageValue,
      );
    } catch (_) {
      // Ignore persistence errors; runtime behavior still applies.
    }
  }

  Future<RuntimeProfile> _loadLastNormalRuntimeProfile() async {
    try {
      final raw =
          await _secureStorage.read(key: _lastNormalRuntimeProfileStorageKey);
      final parsed = runtimeProfileFromStorage(raw);
      if (parsed == RuntimeProfile.emergencyBattery) {
        return RuntimeProfile.normalDirect;
      }
      return parsed;
    } catch (_) {
      return RuntimeProfile.normalDirect;
    }
  }

  Future<void> _persistLastNormalRuntimeProfile(RuntimeProfile profile) async {
    if (profile == RuntimeProfile.emergencyBattery) return;
    try {
      await _secureStorage.write(
        key: _lastNormalRuntimeProfileStorageKey,
        value: profile.storageValue,
      );
    } catch (_) {
      // Ignore persistence errors; runtime behavior still applies.
    }
  }

  Future<void> setRuntimeProfile(RuntimeProfile profile) async {
    if (_runtimeProfile == profile) return;
    final previousProfile = _runtimeProfile;

    if (profile == RuntimeProfile.emergencyBattery) {
      if (previousProfile != RuntimeProfile.emergencyBattery) {
        _lastNormalRuntimeProfile = previousProfile;
        await _persistLastNormalRuntimeProfile(_lastNormalRuntimeProfile);
      }
    } else {
      _lastNormalRuntimeProfile = profile;
      await _persistLastNormalRuntimeProfile(_lastNormalRuntimeProfile);
    }

    _runtimeProfile = profile;
    meshRouter.setRuntimeProfile(profile);
    await _persistRuntimeProfile(profile);
    _applyDiscoveryPolicy();
    notifyListeners();
  }

  Future<void> setNormalRuntimeProfile(RuntimeProfile profile) async {
    if (profile == RuntimeProfile.emergencyBattery) return;
    await setRuntimeProfile(profile);
  }

  Future<void> enableBatterySaver() async {
    await setRuntimeProfile(RuntimeProfile.emergencyBattery);
  }

  Future<void> disableBatterySaver() async {
    await setRuntimeProfile(_lastNormalRuntimeProfile);
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      final current = await Permission.ignoreBatteryOptimizations.status;
      if (!current.isGranted) {
        final result = await Permission.ignoreBatteryOptimizations.request();
        debugPrint('Battery optimization exemption request result: $result');
      }
    } catch (e) {
      debugPrint('Battery optimization exemption request failed: $e');
    }
  }

  void _handleWiFiDiscoveryFailure(WiFiDiscoveryFailure failure) {
    if (!failure.isLocationRelated) return;
    _pendingDiscoveryFailure = failure;
    _pendingDiscoveryFailureVersion++;
    notifyListeners();
  }

  void clearPendingDiscoveryFailure() {
    if (_pendingDiscoveryFailure == null) return;
    _pendingDiscoveryFailure = null;
    notifyListeners();
  }

  Future<bool> openLocationSettings() async {
    final opened = await _batteryStatusService.openLocationSettings();
    if (opened) {
      clearPendingDiscoveryFailure();
    }
    return opened;
  }

  @override
  void dispose() {
    _peerRefreshTimer?.cancel();
    _batteryPollTimer?.cancel();
    _transferPolicySubscription?.cancel();
    _incomingTransferPolicySubscription?.cancel();
    _wifiDiscoveryFailureSubscription?.cancel();
    if (_hasEmergencyBroadcastService) {
      emergencyBroadcastService.dispose();
    }
    super.dispose();
  }

  // Refresh peer discovery (including WiFi Direct)
  Future<void> refreshDiscovery() async {
    try {
      debugPrint('Refreshing discovery services...');

      // Restart mDNS discovery service
      await _discovery.stop();
      await _discovery.start(
          publicKey ?? 'unknown', NetworkConfig.discoveryPort,
          name: displayName);

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

  /// Utility to purge stale peers/routes/endpoints from the local DB.
  Future<Map<String, int>> clearStaleNetworkData({
    Duration stalePeerAge = DatabaseTimerConfig.stalePeerAge,
    Duration staleRouteAge = DatabaseTimerConfig.staleRouteAge,
    Duration staleEndpointAge = DatabaseTimerConfig.staleEndpointAge,
  }) async {
    final keepIds = <String>[];
    final id = publicKey;
    if (id != null && id.isNotEmpty) keepIds.add(id);

    final result = await _db.cleanupStaleNetworkData(
      stalePeerAge: stalePeerAge,
      staleRouteAge: staleRouteAge,
      staleEndpointAge: staleEndpointAge,
      preservePeerIds: keepIds,
    );

    peers = await _db.allPeers();
    await refreshUnreadCounts();
    notifyListeners();
    return result;
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
