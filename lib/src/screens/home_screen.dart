import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_state.dart';
import '../theme.dart';
import 'menu/menu_screen.dart';
import 'mesh/routes_status_screen.dart';
import 'mesh/queued_messages_status_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final displayName = appState.displayName;
    final initials = appState.initials;
    final pub = appState.publicKey ?? 'Generating...';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/image.png',
                height: 28,
                width: 28,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.shield, size: 18, color: AppTheme.bgDeep),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'PeerChat',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: appState.isEmergencyBatteryProfile
                  ? 'Disable Battery Saver'
                  : 'Enable Battery Saver',
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () async {
                  if (appState.isEmergencyBatteryProfile) {
                    await appState.disableBatterySaver();
                  } else {
                    await appState.enableBatterySaver();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.battery_saver_rounded,
                    size: 20,
                    color: appState.isEmergencyBatteryProfile
                        ? AppTheme.warning
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 22),
            tooltip: 'Menu',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MenuScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.bgCard,
        onRefresh: () async {
          await appState.refreshDiscovery();
        },
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── Identity Card ───
                    _IdentitySection(
                      displayName: displayName,
                      initials: initials,
                      publicKey: pub,
                    ),
                    const SizedBox(height: 16),

                    // ─── Mesh Network Status ───
                    _MeshStatusSection(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Identity Section ───
class _IdentitySection extends StatelessWidget {
  final String displayName;
  final String initials;
  final String publicKey;

  const _IdentitySection({
    required this.displayName,
    required this.initials,
    required this.publicKey,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final email = appState.registeredEmail;

    return Container(
      decoration: AppTheme.accentBorderCard(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Name + Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.accent.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Your P2P Identity (Local-only)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // QR Code (Shrunk)
          publicKey == 'Generating...'
              ? const SizedBox(
                  height: 130,
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
                )
              : Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.05),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: QrImageView(
                      data: publicKey, version: QrVersions.auto, size: 160.0),
                ),

          const SizedBox(height: 12),

          // Public key row (Compacted)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: publicKey == 'Generating...' ? null : () {
              Clipboard.setData(ClipboardData(text: publicKey));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Key copied!'), duration: Duration(seconds: 1)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.key, size: 12, color: AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      publicKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.firaCode(
                          fontSize: 10, color: AppTheme.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy_rounded, size: 12, color: AppTheme.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mesh Status Section ───
class _MeshStatusSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final connectedCount = appState.meshRouter.getConnectedPeerIds().length;

        return FutureBuilder(
          future: appState.meshRouter.stats,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                decoration: AppTheme.glassCard(),
                padding: const EdgeInsets.all(20),
                child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
              );
            }

            final stats = snapshot.data!;

            return Container(
              decoration: AppTheme.glassCard(),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header (Compacted)
                  Row(
                    children: [
                      const Icon(Icons.hub_rounded, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Mesh: $connectedCount active',
                          style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: connectedCount > 0 
                              ? AppTheme.online.withValues(alpha: 0.1)
                              : AppTheme.textSecondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: connectedCount > 0 
                                ? AppTheme.online.withValues(alpha: 0.3)
                                : AppTheme.textSecondary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          connectedCount > 0 ? 'LIVE' : 'OFFLINE',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: connectedCount > 0 ? AppTheme.online : AppTheme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _PulsingIndicator(
                        isActive: connectedCount > 0,
                        color: AppTheme.online,
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Stats grid (Smaller)
                  Row(
                    children: [
                      Expanded(
                        child: _MeshStat(
                          icon: Icons.route_rounded,
                          label: 'Routes',
                          value: stats.totalRoutes.toString(),
                          color: AppTheme.primary,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RoutesStatusScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MeshStat(
                          icon: Icons.schedule_send_rounded,
                          label: 'Queued',
                          value: stats.localQueuedMessages.toString(),
                          color: stats.localQueuedMessages > 0
                              ? AppTheme.warning
                              : AppTheme.textSecondary,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const QueuedMessagesStatusScreen.local(),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _MeshStat(
                          icon: Icons.repeat_rounded,
                          label: 'Relayed',
                          value: stats.meshQueuedMessages.toString(),
                          color: stats.meshQueuedMessages > 0
                              ? AppTheme.warning
                              : AppTheme.textSecondary,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const QueuedMessagesStatusScreen.mesh(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MeshStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  const _MeshStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.1)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: color.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w500,
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.4 * _controller.value),
                blurRadius: 8,
                spreadRadius: 4 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}
