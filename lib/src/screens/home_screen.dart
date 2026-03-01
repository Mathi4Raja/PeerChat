import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_state.dart';
import '../models/runtime_profile.dart';
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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.shield, size: 18, color: AppTheme.bgDeep),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                text: TextSpan(
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                  children: [
                    const TextSpan(text: 'PeerChat '),
                    WidgetSpan(
                      child: ShaderMask(
                        shaderCallback: (bounds) =>
                            AppTheme.primaryGradient.createShader(bounds),
                        child: Text(
                          'Secure',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─── Identity Card ───
                _IdentitySection(
                  displayName: displayName,
                  initials: initials,
                  publicKey: pub,
                ),
                const SizedBox(height: 20),
                _RuntimeProfileSection(),
                const SizedBox(height: 20),

                // ─── Mesh Network Status ───
                _MeshStatusSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeProfileSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) {
        final isBatterySaver = appState.isEmergencyBatteryProfile;
        final selectedProfile = isBatterySaver
            ? RuntimeProfile.normalMesh
            : appState.runtimeProfile;

        return Container(
          decoration: AppTheme.glassCard(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppTheme.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Network Profile',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: const [
                  RuntimeProfile.normalDirect,
                  RuntimeProfile.normalMesh,
                ].map((profile) {
                  final selected = selectedProfile == profile;
                  return ChoiceChip(
                    label: Text(profile.shortLabel),
                    selected: selected,
                    onSelected: isBatterySaver
                        ? null
                        : (_) => appState.setNormalRuntimeProfile(profile),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                isBatterySaver
                    ? 'Battery Saver active. Network profile selection is disabled and routing stays on Mesh (passive). Disable Battery Saver to switch Direct/Mesh.'
                    : appState.runtimeProfile.description,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
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
    return Container(
      decoration: AppTheme.accentBorderCard(),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar + name
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
              child: Text(
                initials,
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            displayName,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              'LOCAL-ONLY',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
                letterSpacing: 0.8,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // QR Code
          publicKey == 'Generating...'
              ? const SizedBox(
                  height: 160,
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppTheme.primary)),
                )
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        width: 2),
                  ),
                  child: QrImageView(
                      data: publicKey, version: QrVersions.auto, size: 160.0),
                ),

          const SizedBox(height: 14),

          // Public key row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.key, size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    publicKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.firaCode(
                        fontSize: 10, color: AppTheme.textSecondary),
                  ),
                ),
                if (publicKey != 'Generating...')
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: publicKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Public key copied!')),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.copy_rounded,
                          size: 14, color: AppTheme.accent),
                    ),
                  ),
              ],
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
        final discoveredCount = appState.activePeers.length;

        return FutureBuilder(
          future: appState.meshRouter.stats,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                decoration: AppTheme.glassCard(),
                padding: const EdgeInsets.all(20),
                child: const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary)),
              );
            }

            final stats = snapshot.data!;

            return Container(
              decoration: AppTheme.glassCard(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.hub_rounded,
                            color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mesh Network',
                              style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary),
                            ),
                            Text(
                              '$connectedCount connected · $discoveredCount discovered',
                              style: GoogleFonts.inter(
                                  fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: connectedCount > 0
                              ? const LinearGradient(
                                  colors: [AppTheme.online, Color(0xFF81C784)])
                              : null,
                          color: connectedCount > 0
                              ? null
                              : AppTheme.textSecondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: connectedCount > 0
                                    ? Colors.white
                                    : AppTheme.textSecondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              connectedCount > 0 ? 'LIVE' : 'IDLE',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: connectedCount > 0
                                    ? AppTheme.bgDeep
                                    : AppTheme.textSecondary,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Stats grid
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
                      const SizedBox(width: 8),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MeshStat(
                          icon: Icons.hub_rounded,
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

                  const SizedBox(height: 10),
                  Text(
                    'Queued: local messages waiting for route/connection. Relayed: mesh-origin messages waiting for next hop.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
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
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: color.withValues(alpha: 0.7),
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

