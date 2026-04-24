import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:peerchat_secure/src/screens/web_share_files_screen.dart';
import 'package:peerchat_secure/src/screens/web_share_log_screen.dart';
import 'package:peerchat_secure/src/services/web_share_service.dart';
import 'package:peerchat_secure/src/theme.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_state.dart';

class WebShareScreen extends StatefulWidget {
  const WebShareScreen({super.key});

  @override
  State<WebShareScreen> createState() => _WebShareScreenState();
}

class _WebShareScreenState extends State<WebShareScreen> {
  late WebShareService _service;
  bool _isInit = true;
  Timer? _statusRefreshTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInit) {
      final appState = Provider.of<AppState>(context);
      _service = appState.webShareService;
      _isInit = false;
      
      // Start periodic status refresh
      _statusRefreshTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestWebShareIsolationPermissions() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final hasPermission = await appState.canControlBluetoothForWebShare();
    if (!hasPermission) {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Bluetooth Control Permission'),
          content: const Text(
            'PeerChat can pause Bluetooth automatically while Web Share is running so hotspot transfers stay isolated '
            'from nearby peer discovery traffic.'
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
              child: const Text('Grant'),
            ),
          ],
        ),
      );

      if (proceed == true) {
        await appState.deviceService.openSystemSettingsPermission();
      }
    }
  }

  void _toggleServer() async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (_service.isRunning) {
      await _service.stop();
      await appState.setWebShareIsolation(false);
    } else {
      final hasPermission = await appState.canControlBluetoothForWebShare();
      if (!hasPermission) {
        await _requestWebShareIsolationPermissions();
      }

      await appState.setWebShareIsolation(true);
      try {
        await _service.start();
      } catch (_) {
        await appState.setWebShareIsolation(false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start Web Share server')),
        );
        return;
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Share'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.appBarGradient,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.glassCard(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.wifi_tethering, color: AppTheme.primary, size: 24),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text('Local Hotspot Sharing', 
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!_service.isRunning) ...[
                          const SizedBox(height: 12),
                          Text(
                            '1. Turn on Mobile Hotspot.\n'
                            '2. Let receiver connect to your Wi-Fi.\n'
                            '3. Start the server then add files.',
                            style: TextStyle(
                              color: AppTheme.textSecondary, 
                              height: 1.6, 
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (_service.isRunning) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: Column(
                              children: [
                                if (_service.currentUrl != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppTheme.primary.withValues(alpha: 0.15),
                                          blurRadius: 20,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: QrImageView(
                                      data: _service.currentUrl!,
                                      version: QrVersions.auto,
                                      size: 145.0,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildCopyableUrl(_service.currentUrl!),
                                ] else ...[
                                  const SizedBox(height: 16),
                                  const CircularProgressIndicator(strokeWidth: 3),
                                  const SizedBox(height: 12),
                                  Text('Preparing environment...', 
                                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)
                                  ),
                                ]
                              ],
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_service.isRunning) ...[
                        Expanded(
                          child: _buildActionShortcut(
                            context, 
                            icon: Icons.cloud_upload_rounded, 
                            label: 'Add Files', 
                            screen: WebShareHostedFilesScreen(service: _service),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: _buildActionShortcut(
                          context, 
                          icon: Icons.history_rounded, 
                          label: 'Transfer Log', 
                          screen: WebShareLogScreen(service: _service),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  if (_service.isRunning) ...[
                    const SizedBox(height: 16),
                    // Performance Hint
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded, size: 16, color: AppTheme.accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'To increase transfer speed, turn off Bluetooth.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary.withValues(alpha: 0.8),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  const SizedBox(height: 12),

                  // Real-time Hardware Status
                  _buildHardwareStatusRow(appState),

                  const SizedBox(height: 16),

                  // Start/Stop Button
                  ElevatedButton.icon(
                    onPressed: _toggleServer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _service.isRunning ? AppTheme.bgSurface : AppTheme.primary,
                      foregroundColor: _service.isRunning ? AppTheme.primary : AppTheme.bgDeep,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: _service.isRunning ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5) : null,
                    ),
                    icon: Icon(_service.isRunning ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded, size: 24),
                    label: Text(_service.isRunning ? 'Stop Server' : 'Start Sharing', 
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)
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

  Widget _buildActionShortcut(BuildContext context, {required IconData icon, required String label, required Widget screen}) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => screen),
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, 
                maxLines: 1, 
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyableUrl(String url) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL copied to clipboard')),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(url, 
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16, 
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppTheme.textPrimary,
                )
              ),
            ),
            const SizedBox(width: 14),
            const Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildHardwareStatusRow(AppState appState) {
    return FutureBuilder<List<bool?>>(
      future: Future.wait<bool?>([
        appState.deviceService.isBluetoothEnabled(),
        appState.deviceService.isHotspotEnabled(),
      ]),
      builder: (context, snapshot) {
        final btEnabled = snapshot.data?[0] ?? true;
        final hotspotEnabled = snapshot.data?[1];
        return Row(
          children: [
            Expanded(
              child: _buildStatusMiniCard(
                icon: btEnabled ? Icons.bluetooth_rounded : Icons.bluetooth_disabled_rounded,
                label: 'Bluetooth',
                status: btEnabled ? 'ON' : 'OFF',
                isActive: _service.isRunning && btEnabled,
                color: (_service.isRunning && btEnabled) ? Colors.amber : Colors.blueAccent,
                onTap: _service.isRunning ? () async {
                  final hasPerm = await appState.canControlBluetoothForWebShare();
                  if (hasPerm) {
                    await appState.deviceService.toggleBluetooth(!btEnabled);
                  }
                  // Reliable fallback for modern Android: open system settings
                  await appState.deviceService.openBluetoothSettings();
                } : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatusMiniCard(
                icon: Icons.wifi_tethering_rounded,
                label: 'Hotspot',
                status: hotspotEnabled == null ? 'UNKNOWN' : (hotspotEnabled ? 'ON' : 'OFF'),
                isActive: hotspotEnabled == false,
                color: hotspotEnabled == false ? Colors.amber : Colors.orangeAccent,
                onTap: () => appState.deviceService.openHotspotSettings(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusMiniCard({
    required IconData icon,
    required String label,
    required String status,
    required bool isActive,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          debugPrint('WebShareScreen: MiniCard Tapped - $label');
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? color.withValues(alpha: 0.5) : AppTheme.primary.withValues(alpha: 0.1),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: isActive ? color : AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
                    Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? color : AppTheme.textPrimary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingIndicator extends StatefulWidget {
  final bool isActive;
  final Color color;

  const _PulsingIndicator({required this.isActive, required this.color});

  @override
  State<_PulsingIndicator> createState() => _PulsingIndicatorState();
}

class _PulsingIndicatorState extends State<_PulsingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (widget.isActive) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      return Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: AppTheme.textSecondary,
          shape: BoxShape.circle,
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * _controller.value),
                blurRadius: 6,
                spreadRadius: 3 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
