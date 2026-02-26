import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/file_transfer.dart';
import '../config/limits_config.dart';
import '../config/identity_ui_config.dart';
import '../config/timer_config.dart';
import '../theme.dart';
import '../utils/file_size_formatter.dart';
import '../utils/name_generator.dart';
import 'home_screen.dart';
import 'chats_list_screen.dart';
import 'peers_screen.dart';
import 'emergency_broadcast_screen.dart';
import 'debug/routing_debug_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _lastDiscoveryFailureVersion = 0;
  bool _isLocationDialogOpen = false;
  bool _isIncomingTransferDialogOpen = false;
  bool _incomingTransferListenerAttached = false;
  int _emergencyUnreadCount = 0;
  final List<FileTransferSession> _pendingIncomingTransfers = [];
  StreamSubscription<FileTransferSession>? _incomingTransferSubscription;
  StreamSubscription<FileTransferSession>? _transferUpdateSubscription;
  StreamSubscription<Map<String, Object?>>? _broadcastBadgeSubscription;
  final Set<String> _shownSenderTransferToasts = {};
  final Map<String, FileTransferState> _lastTransferStateByFileId = {};
  String? _activeIncomingDialogFileId;

  final List<Widget> _screens = const [
    HomeScreen(),
    ChatsListScreen(),
    PeersScreen(),
    EmergencyBroadcastScreen(),
    RoutingDebugScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_incomingTransferListenerAttached) return;
    _incomingTransferListenerAttached = true;

    final appState = Provider.of<AppState>(context, listen: false);
    _incomingTransferSubscription =
        appState.fileTransferService.onIncomingRequest.listen((session) {
      _pendingIncomingTransfers.add(session);
      _scheduleIncomingTransferDialogIfNeeded(appState);
    });
    _transferUpdateSubscription =
        appState.fileTransferService.onTransferUpdate.listen((session) {
      if (!mounted) return;
      final previousState = _lastTransferStateByFileId[session.fileId];
      _lastTransferStateByFileId[session.fileId] = session.state;

      if (session.direction == TransferDirection.receiving &&
          session.state == FileTransferState.cancelled) {
        _pendingIncomingTransfers
            .removeWhere((s) => s.fileId == session.fileId);
        if (_isIncomingTransferDialogOpen &&
            _activeIncomingDialogFileId == session.fileId) {
          _activeIncomingDialogFileId = null;
          Navigator.of(context, rootNavigator: true).maybePop();
        }
        _lastTransferStateByFileId.remove(session.fileId);
        return;
      }

      if (session.direction == TransferDirection.receiving &&
          session.state == FileTransferState.paused &&
          previousState != FileTransferState.paused) {
        final senderName = _peerDisplayName(appState, session.peerId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$senderName paused sending ${session.metadata.fileName}',
            ),
          ),
        );
      }

      if (session.direction == TransferDirection.receiving &&
          session.state == FileTransferState.transferring &&
          previousState == FileTransferState.paused) {
        final senderName = _peerDisplayName(appState, session.peerId);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$senderName resumed sending ${session.metadata.fileName}',
            ),
          ),
        );
      }

      if (session.state == FileTransferState.completed ||
          session.state == FileTransferState.cancelled ||
          session.state == FileTransferState.failed) {
        _lastTransferStateByFileId.remove(session.fileId);
      }

      if (session.direction != TransferDirection.sending) return;

      if (session.state == FileTransferState.cancelled &&
          session.cancelledByPeer) {
        final key = '${session.fileId}:sender_cancelled_by_peer';
        if (!_shownSenderTransferToasts.contains(key)) {
          _shownSenderTransferToasts.add(key);
          final peerName = _peerDisplayName(appState, session.peerId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$peerName cancelled ${session.metadata.fileName}',
              ),
            ),
          );
        }
      }

      if (session.state == FileTransferState.completed) {
        final key = '${session.fileId}:sender_completed';
        if (!_shownSenderTransferToasts.contains(key)) {
          _shownSenderTransferToasts.add(key);
          final peerName = _peerDisplayName(appState, session.peerId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File sent to $peerName: ${session.metadata.fileName}',
              ),
            ),
          );
        }
      }

      if (session.state == FileTransferState.failed && session.rejectedByPeer) {
        final key = '${session.fileId}:sender_rejected';
        if (!_shownSenderTransferToasts.contains(key)) {
          _shownSenderTransferToasts.add(key);
          final peerName = _peerDisplayName(appState, session.peerId);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$peerName rejected ${session.metadata.fileName}',
              ),
            ),
          );
        }
      }
      _lastTransferStateByFileId.remove(session.fileId);
    });
    _broadcastBadgeSubscription =
        appState.emergencyBroadcastService.onBroadcastMessage.listen((event) {
      if (!mounted) return;
      final senderId = (event['sender_id'] as String?) ?? '';
      final localPeerId = appState.publicKey ?? '';
      if (senderId.isEmpty) return;
      if (localPeerId.isNotEmpty && senderId == localPeerId) return;
      if (_currentIndex == 3) return;
      setState(() {
        _emergencyUnreadCount++;
      });
    });
  }

  @override
  void dispose() {
    _incomingTransferSubscription?.cancel();
    _transferUpdateSubscription?.cancel();
    _broadcastBadgeSubscription?.cancel();
    super.dispose();
  }

  void _scheduleDiscoveryFailureDialogIfNeeded(AppState appState) {
    final failure = appState.pendingDiscoveryFailure;
    if (failure == null) {
      return;
    }
    if (_isLocationDialogOpen ||
        appState.pendingDiscoveryFailureVersion ==
            _lastDiscoveryFailureVersion) {
      return;
    }

    _lastDiscoveryFailureVersion = appState.pendingDiscoveryFailureVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isLocationDialogOpen) return;
      _showLocationFailureDialog(appState, failure.userMessage);
    });
  }

  Future<void> _showLocationFailureDialog(
      AppState appState, String message) async {
    _isLocationDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Location Required'),
          content: Text(
            '$message\n\nEnable location to restore peer discovery and auto-reconnect.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                appState.clearPendingDiscoveryFailure();
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final opened = await appState.openLocationSettings();
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open settings automatically'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
    _isLocationDialogOpen = false;
  }

  void _scheduleIncomingTransferDialogIfNeeded(AppState appState) {
    if (_isIncomingTransferDialogOpen ||
        _isLocationDialogOpen ||
        _pendingIncomingTransfers.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _isIncomingTransferDialogOpen ||
          _isLocationDialogOpen ||
          _pendingIncomingTransfers.isEmpty) {
        return;
      }
      final session = _pendingIncomingTransfers.removeAt(0);
      await _showIncomingTransferDialog(appState, session);
      if (mounted) {
        _scheduleIncomingTransferDialogIfNeeded(appState);
      }
    });
  }

  String _peerDisplayName(AppState appState, String peerId) {
    for (final peer in appState.peers) {
      if (peer.id != peerId) continue;
      final displayName = peer.displayName.trim();
      if (displayName.isNotEmpty &&
          displayName != IdentityUiConfig.defaultDisplayName) {
        return displayName;
      }
      break;
    }
    return NameGenerator.generateShortName(peerId);
  }

  Future<void> _showIncomingTransferDialog(
    AppState appState,
    FileTransferSession session,
  ) async {
    _isIncomingTransferDialogOpen = true;
    _activeIncomingDialogFileId = session.fileId;
    final senderName = _peerDisplayName(appState, session.peerId);

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Incoming File'),
          content: Text(
            '$senderName is sending:\n'
            '${session.metadata.fileName}\n'
            '${formatFileSizeBy1024(session.metadata.fileSize)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'reject'),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'accept'),
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );

    if (_activeIncomingDialogFileId != session.fileId) {
      _isIncomingTransferDialogOpen = false;
      return;
    }

    if (result == 'accept') {
      await appState.fileTransferService.acceptTransfer(session.fileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accepted file from $senderName')),
        );
      }
    } else if (result == 'reject') {
      await appState.fileTransferService.rejectTransfer(session.fileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rejected file from $senderName')),
        );
      }
    }

    _activeIncomingDialogFileId = null;
    _isIncomingTransferDialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    _scheduleDiscoveryFailureDialogIfNeeded(appState);
    _scheduleIncomingTransferDialogIfNeeded(appState);
    final int totalUnread =
        appState.unreadCounts.values.fold(0, (sum, count) => sum + count);

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      icon: Icons.home_rounded,
                      label: 'Home',
                      isActive: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.chat_rounded,
                      label: 'Messages',
                      isActive: _currentIndex == 1,
                      badge: totalUnread > 0 ? totalUnread : null,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.radar_rounded,
                      label: 'Peers',
                      isActive: _currentIndex == 2,
                      onTap: () => setState(() => _currentIndex = 2),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.sos_rounded,
                      label: 'Emergency',
                      isActive: _currentIndex == 3,
                      badge: _emergencyUnreadCount > 0
                          ? _emergencyUnreadCount
                          : null,
                      onTap: () => setState(() {
                        _currentIndex = 3;
                        _emergencyUnreadCount = 0;
                      }),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.developer_board_rounded,
                      label: 'Debug',
                      isActive: _currentIndex == 4,
                      onTap: () => setState(() => _currentIndex = 4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final int? badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badgeLabel = badge == null
        ? null
        : (badge! > UiLimits.badgeDisplayCap
            ? '${UiLimits.badgeDisplayCap}+'
            : '${badge!}');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: UiTimerConfig.navItemAnimation,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                ),
                if (badgeLabel != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.danger.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Text(
                        badgeLabel,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
