import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../theme.dart';
import '../web_share_screen.dart';

class ShareAppScreen extends StatefulWidget {
  const ShareAppScreen({super.key});

  @override
  State<ShareAppScreen> createState() => _ShareAppScreenState();
}

class _ShareAppScreenState extends State<ShareAppScreen> {
  static const String _downloadUrl =
      'https://github.com/Mathi4Raja/P2P-app/releases/download/v1.0.0/PeerChat.apk';
  static const String _shareText =
      'Try PeerChat — serverless, encrypted P2P messaging. No account needed.\n$_downloadUrl';

  bool _isStartingWebShare = false;

  // ── Helpers ─────────────────────────────────────────────

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _downloadUrl));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download link copied'), duration: Duration(seconds: 1)));
  }

  Future<void> _openLink(BuildContext context) async {
    final uri = Uri.parse(_downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')));
    }
  }

  /// Native Android share sheet — includes Quick Share, Bluetooth, Gmail, and more.
  Future<void> _shareNative() async {
    await Share.share(_shareText, subject: 'PeerChat App');
  }

  /// Auto-starts the WebShare server then navigates to the screen.
  Future<void> _openWebShare(BuildContext context) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final webShareService = appState.webShareService;

    setState(() => _isStartingWebShare = true);
    try {
      if (!webShareService.isRunning) {
        await appState.setWebShareIsolation(true);
        try {
          await webShareService.start();
        } catch (e) {
          await appState.setWebShareIsolation(false);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not start Web Share server')));
          }
          return;
        }
      }
    } finally {
      if (mounted) setState(() => _isStartingWebShare = false);
    }

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: appState,
          child: const WebShareScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Share App', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [

          // ─── Native Share (Quick Share / Bluetooth) ───
          _SectionCard(
            icon: Icons.share_rounded,
            iconColor: AppTheme.primary,
            title: 'Share via Device',
            subtitle: 'Opens the Android share sheet — includes Quick Share, Bluetooth, Gmail, and more.',
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _shareNative,
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text('Share with...'),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ─── Web Share (auto-host) ───
          _SectionCard(
            icon: Icons.wifi_tethering_rounded,
            iconColor: AppTheme.accent,
            title: 'Web Share (Local Wi-Fi)',
            subtitle: 'Host the APK over your mobile hotspot. Nearby devices download it in their browser — no internet needed.',
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isStartingWebShare ? null : () => _openWebShare(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent.withValues(alpha: 0.14),
                  foregroundColor: AppTheme.accent,
                ),
                icon: _isStartingWebShare
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_circle_outline_rounded, size: 16),
                label: Text(_isStartingWebShare ? 'Starting server…' : 'Start & Open Web Share'),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // ─── Direct APK Link ───
          _SectionCard(
            icon: Icons.link_rounded,
            iconColor: AppTheme.textSecondary,
            title: 'Direct Download Link',
            subtitle: 'Copy and paste the APK link anywhere.',
            child: Column(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _copyLink(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.bgDeep, borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Expanded(
                        child: Text(_downloadUrl, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.firaCode(fontSize: 9.5, color: AppTheme.textSecondary))),
                      const SizedBox(width: 6),
                      const Icon(Icons.copy_rounded, size: 13, color: AppTheme.accent),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyLink(context),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openLink(context),
                      icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                      label: const Text('Open'),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle, required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 7),
          Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ]),
        const SizedBox(height: 3),
        Text(subtitle, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}
