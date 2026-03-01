import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../theme.dart';

class MeshStatusCard extends StatelessWidget {
  const MeshStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return FutureBuilder(
          future: appState.meshRouter.stats,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Container(
                decoration: AppTheme.glassCard(),
                padding: const EdgeInsets.all(20),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              );
            }

            final stats = snapshot.data!;

            return Container(
              decoration: AppTheme.glassCard(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Header ───
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.router, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Mesh Network',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'P2P',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.bgDeep,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ─── Stat Chips ───
                  Row(
                    children: [
                      Expanded(
                        child: _StatChip(
                          icon: Icons.route,
                          label: 'Routes',
                          value: stats.totalRoutes.toString(),
                          color: AppTheme.online,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatChip(
                          icon: Icons.queue,
                          label: 'Queued',
                          value: stats.localQueuedMessages.toString(),
                          color: stats.localQueuedMessages > 0
                              ? AppTheme.warning
                              : AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatChip(
                          icon: Icons.hub,
                          label: 'Relayed',
                          value: stats.meshQueuedMessages.toString(),
                          color: stats.meshQueuedMessages > 0
                              ? AppTheme.warning
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Queued = local messages waiting for route/connection. Relayed = mesh-origin messages waiting for next hop.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        appState.isBatteryLow
                            ? Icons.battery_alert_rounded
                            : (appState.isCharging
                                ? Icons.battery_charging_full_rounded
                                : Icons.battery_std_rounded),
                        size: 14,
                        color: appState.isBatteryLow
                            ? AppTheme.warning
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          appState.isBatteryLow
                              ? 'Battery low (${appState.batteryLevel}%). Discovery is throttled.'
                              : 'Battery ${appState.batteryLevel}%${appState.isCharging ? ' • Charging' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: color.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

