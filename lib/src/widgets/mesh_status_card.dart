import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
                      Text(
                        'Mesh Network',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(
                        icon: Icons.route,
                        label: 'Routes',
                        value: stats.totalRoutes.toString(),
                        color: AppTheme.online,
                      ),
                      _StatChip(
                        icon: Icons.queue,
                        label: 'Queued',
                        value: stats.queuedMessages.toString(),
                        color: stats.queuedMessages > 0
                            ? AppTheme.warning
                            : AppTheme.textSecondary,
                      ),
                      _StatChip(
                        icon: Icons.check_circle_outline,
                        label: 'Acks',
                        value: stats.pendingAcks.toString(),
                        color: stats.pendingAcks > 0
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                      if (stats.blockedPeers > 0)
                        _StatChip(
                          icon: Icons.block,
                          label: 'Blocked',
                          value: stats.blockedPeers.toString(),
                          color: AppTheme.danger,
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
