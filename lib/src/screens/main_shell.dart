import 'dart:async';

import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config/limits_config.dart';
import '../config/timer_config.dart';
import '../services/menu_settings_service.dart';
import '../services/local_notification_service.dart';
import '../services/notification_sound_service.dart';
import '../theme.dart';
import '../utils/name_generator.dart';
import 'chat_screen.dart';
import 'chats_list_screen.dart';
import 'debug/routing_debug_screen.dart';
import 'emergency_broadcast_screen.dart';
import 'home_screen.dart';
import 'peers_screen.dart';
import 'web_share_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _lastDiscoveryFailureVersion = 0;
  bool _isLocationDialogOpen = false;
  bool _notificationHandlingInitialized = false;
  int _emergencyUnreadCount = 0;
  StreamSubscription<Map<String, Object?>>? _broadcastBadgeSubscription;
  StreamSubscription? _chatMessageSoundSubscription;
  StreamSubscription<NotificationTapAction>? _notificationTapSubscription;
  StreamSubscription? _webShareEventSubscription;
  StreamSubscription? _webShareUploadSubscription;
  StreamSubscription? _directShareRequestSubscription;
  StreamSubscription? _directShareCompletionSubscription;
  final NotificationSoundService _notificationSoundService =
      NotificationSoundService();
  final LocalNotificationService _localNotificationService =
      LocalNotificationService();
  String? _lastNotificationTapKey;
  DateTime? _lastNotificationTapHandledAt;

  final List<Widget> _screens = const [
    HomeScreen(),
    ChatsListScreen(),
    PeersScreen(),
    EmergencyBroadcastScreen(),
    WebShareScreen(),
    RoutingDebugScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_notificationHandlingInitialized) {
      _notificationHandlingInitialized = true;
      unawaited(_initializeNotificationHandling());
    }

    _chatMessageSoundSubscription ??=
        Provider.of<AppState>(context, listen: false)
            .meshRouter
            .onMessageReceived
            .listen((chatMessage) {
      if (!mounted) return;
      if (chatMessage.isSentByMe) return;
      final settings = Provider.of<MenuSettingsController>(context, listen: false)
          .notifications;
      if (settings.chatMessages) {
        final senderLabel = NameGenerator.generateShortName(chatMessage.peerId);
        unawaited(
          _localNotificationService.showChatMessage(
            peerId: chatMessage.peerId,
            senderLabel: senderLabel,
            content: chatMessage.content,
            playSound: settings.sound,
          ),
        );
      } else if (settings.sound) {
        unawaited(_notificationSoundService.playIncoming());
      }
    });

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
      final settings = Provider.of<MenuSettingsController>(context, listen: false)
          .notifications;
      final content = (event['content'] as String?) ?? '';
      final messageId = (event['id'] as String?) ?? '';
      if (settings.broadcastChannel &&
          _isMentionedBroadcastForLocalUser(
            content: content,
            localPeerId: localPeerId,
          )) {
        final senderLabel = NameGenerator.generateShortName(senderId);
        final body = _extractBroadcastBody(content);
        unawaited(
          _localNotificationService.showBroadcastMention(
            messageId: messageId,
            senderLabel: senderLabel,
            content: body,
            playSound: settings.sound,
          ),
        );
      }
      if (settings.sound && settings.broadcastChannel) {
        unawaited(_notificationSoundService.playBroadcastIncomingAlert());
      }
      if (_currentIndex == 3) return;
      setState(() {
        _emergencyUnreadCount++;
      });
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final webShareService = appState.webShareService;
    _webShareEventSubscription ??= webShareService.onEvent.listen((event) {
      if (!mounted) return;
      if (event.contains('Received:')) {
        final fileName = event.split('Received: ').last;
        _showSuccessToast(context, 'Received: $fileName', isWebShare: true);
      }
    });

    _webShareUploadSubscription ??= webShareService.onUploadRequest.listen((request) {
      if (!mounted) return;
      _showIncomingTransferDialog(
        context: context,
        senderLabel: "via Browser",
        fileName: request.filename,
        fileSize: request.size,
        icon: Icons.language_rounded,
        accentColor: Colors.blue,
        onAccept: () => webShareService.respondToUpload(request.id, true),
        onReject: () => webShareService.respondToUpload(request.id, false),
      );
    });

    final fileTransferService = appState.fileTransferService;
    _directShareRequestSubscription ??= fileTransferService.onIncomingRequest.listen((session) {
      if (!mounted) return;
      _showIncomingTransferDialog(
        context: context,
        senderLabel: NameGenerator.generateShortName(session.peerId),
        fileName: session.metadata.name,
        fileSize: session.metadata.size,
        icon: Icons.link_rounded,
        accentColor: Colors.purpleAccent,
        onAccept: () => fileTransferService.acceptTransfer(session.fileId),
        onReject: () => fileTransferService.rejectTransfer(session.fileId),
      );
    });

    _directShareCompletionSubscription ??= fileTransferService.onTransferCompleted.listen((session) {
      if (!mounted) return;
      if (session.isIncoming) {
        _showSuccessToast(context, 'Received: ${session.metadata.name}', isWebShare: false);
      } else {
        _showSuccessToast(context, 'Sent: ${session.metadata.name}', isWebShare: false);
      }
    });
  }

  Future<void> _initializeNotificationHandling() async {
    await _localNotificationService.init();
    if (!mounted) return;

    _notificationTapSubscription ??=
        _localNotificationService.onTapAction.listen(_handleNotificationTap);
    final pendingTap = _localNotificationService.takePendingTapAction();
    if (pendingTap != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleNotificationTap(pendingTap);
      });
    }
  }

  @override
  void dispose() {
    _chatMessageSoundSubscription?.cancel();
    _broadcastBadgeSubscription?.cancel();
    _notificationTapSubscription?.cancel();
    _webShareEventSubscription?.cancel();
    _webShareUploadSubscription?.cancel();
    _directShareRequestSubscription?.cancel();
    _directShareCompletionSubscription?.cancel();
    unawaited(_localNotificationService.dispose());
    unawaited(_notificationSoundService.dispose());
    super.dispose();
  }

  bool _isMentionedBroadcastForLocalUser({
    required String content,
    required String localPeerId,
  }) {
    if (content.isEmpty || localPeerId.isEmpty) return false;
    if (!content.startsWith('↪ ')) return false;

    final newlineIndex = content.indexOf('\n');
    if (newlineIndex <= 2) return false;

    final header = content.substring(2, newlineIndex).trim();
    final colonIndex = header.indexOf(':');
    if (colonIndex <= 0) return false;

    final targetLabel = header.substring(0, colonIndex).trim().toLowerCase();
    if (targetLabel.isEmpty) return false;

    final localShort = NameGenerator.generateShortName(localPeerId).toLowerCase();
    final localFull = NameGenerator.generateName(localPeerId).toLowerCase();
    return targetLabel == localShort || targetLabel == localFull;
  }

  String _extractBroadcastBody(String content) {
    final newlineIndex = content.indexOf('\n');
    if (newlineIndex > 0 && newlineIndex < content.length - 1) {
      return content.substring(newlineIndex + 1).trim();
    }
    return content;
  }

  Future<void> _showIncomingTransferDialog({
    required BuildContext context,
    required String senderLabel,
    required String fileName,
    required int fileSize,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onAccept,
    required VoidCallback onReject,
  }) async {
    if (!mounted) return;
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.bgCard.withValues(alpha: 0.95),
        surfaceTintColor: accentColor.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Incoming Transfer', 
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(senderLabel, 
              style: TextStyle(color: accentColor, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Column(
                children: [
                  Text(fileName, 
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text('${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    onReject();
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    onAccept();
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSuccessToast(BuildContext context, String message, {required bool isWebShare}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isWebShare ? Icons.language_rounded : Icons.link_rounded, 
              color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, 
                style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
          ],
        ),
        backgroundColor: isWebShare ? Colors.blue.shade700 : Colors.purple.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleNotificationTap(NotificationTapAction action) {
    if (!mounted) return;
    final tapKey = '${action.target.name}:${action.peerId ?? ''}';
    final now = DateTime.now();
    if (_lastNotificationTapKey == tapKey &&
        _lastNotificationTapHandledAt != null &&
        now.difference(_lastNotificationTapHandledAt!) <
            const Duration(milliseconds: 1500)) {
      return;
    }
    _lastNotificationTapKey = tapKey;
    _lastNotificationTapHandledAt = now;

    if (action.target == NotificationTapTarget.emergency) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        _currentIndex = 3;
        _emergencyUnreadCount = 0;
      });
      return;
    }

    final peerId = action.peerId;
    if (peerId == null || peerId.isEmpty) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _currentIndex = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        ChatScreen.route(preselectedPeerId: peerId),
      );
    });
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
                      icon: Icons.wifi_tethering,
                      label: 'Web Share',
                      isActive: _currentIndex == 4,
                      onTap: () => setState(() => _currentIndex = 4),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      icon: Icons.developer_board_rounded,
                      label: 'Debug',
                      isActive: _currentIndex == 5,
                      onTap: () => setState(() => _currentIndex = 5),
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
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: UiTimerConfig.navItemAnimation,
              width: isActive ? 4 : 0,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
