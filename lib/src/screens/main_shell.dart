import 'dart:async';

import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config/limits_config.dart';
import '../config/timer_config.dart';
import '../theme.dart';
import 'chats_list_screen.dart';
import 'debug/routing_debug_screen.dart';
import 'emergency_broadcast_screen.dart';
import 'home_screen.dart';
import 'peers_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _lastDiscoveryFailureVersion = 0;
  bool _isLocationDialogOpen = false;
  int _emergencyUnreadCount = 0;
  StreamSubscription<Map<String, Object?>>? _broadcastBadgeSubscription;

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
    _broadcastBadgeSubscription ??=
        Provider.of<AppState>(context, listen: false)
            .emergencyBroadcastService
            .onBroadcastMessage
            .listen((event) {
      if (!mounted) return;
      final appState = Provider.of<AppState>(context, listen: false);
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

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    _scheduleDiscoveryFailureDialogIfNeeded(appState);
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
            : '$badge');

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
