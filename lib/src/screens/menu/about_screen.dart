import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _appVersion = '1.0.0';
  static const String _baseUrl = 'https://peerchat.mathi.live';
  static const String _changelogUrl = '$_baseUrl/changelog';
  static const String _tosUrl = '$_baseUrl/tos';
  static const String _policiesUrl = '$_baseUrl/policies';
  static const String _githubUrl = 'https://github.com/Mathi4Raja/P2P-app';

  Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('About', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield, size: 28, color: AppTheme.bgDeep),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PeerChat', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Version $_appVersion — Secure Mesh', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      const SizedBox(height: 2),
                      Text('Serverless · E2E Encrypted · Open Source', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.accent.withValues(alpha: 0.8), fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _LinkCard(icon: Icons.history_rounded, iconColor: AppTheme.primary, title: 'Changelog', subtitle: "What's new in recent versions", onTap: () => _launch(context, _changelogUrl)),
          _LinkCard(icon: Icons.article_outlined, iconColor: AppTheme.accent, title: 'Terms of Service', subtitle: 'Usage terms and conditions', onTap: () => _launch(context, _tosUrl)),
          _LinkCard(icon: Icons.shield_outlined, iconColor: AppTheme.accentPurple, title: 'Privacy Policy', subtitle: 'How we handle your data', onTap: () => _launch(context, _policiesUrl)),
          _LinkCard(icon: Icons.code_rounded, iconColor: AppTheme.textSecondary, title: 'Source Code', subtitle: 'Audit the protocol on GitHub', onTap: () => _launch(context, _githubUrl)),
        ],
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkCard({required this.icon, required this.iconColor, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Icon(Icons.open_in_new_rounded, color: AppTheme.textSecondary.withValues(alpha: 0.5), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
