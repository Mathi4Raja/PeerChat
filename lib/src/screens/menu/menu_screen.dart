import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import '../../theme.dart';
import 'about_screen.dart';
import 'account_settings_screen.dart';
import 'help_faq_screen.dart';
import 'notification_settings_screen.dart';
import 'share_app_screen.dart';
import 'support_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Menu',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/image.png',
                    height: 40,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.shield,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PeerChat',
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Version 1.0.0 (Secure Mesh)',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _MenuTile(
            icon: Icons.person_rounded,
            iconColor: AppTheme.primary,
            title: 'Account',
            subtitle: 'Name and profile picture',
            onTap: () => _open(context, const AccountSettingsScreen()),
          ),
          _MenuTile(
            icon: Icons.notifications_active_rounded,
            iconColor: AppTheme.accentPurple,
            title: 'Notifications',
            subtitle: 'Sound, messages/broadcast',
            onTap: () => _open(context, const NotificationSettingsScreen()),
          ),
          _MenuTile(
            icon: Icons.share_rounded,
            iconColor: AppTheme.accent,
            title: 'Share This App',
            subtitle: 'Download link and offline sharing',
            onTap: () => _open(context, const ShareAppScreen()),
          ),
          _MenuTile(
            icon: Icons.favorite_rounded,
            iconColor: Colors.pinkAccent,
            title: 'Support',
            subtitle: 'Donate and feedback',
            onTap: () => _open(context, const SupportScreen()),
          ),
          _MenuTile(
            icon: Icons.help_outline_rounded,
            iconColor: Colors.amberAccent,
            title: 'Help (FAQ)',
            subtitle: 'Common questions and answers',
            onTap: () => _open(context, const HelpFaqScreen()),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
            iconColor: AppTheme.textSecondary,
            title: 'About',
            subtitle: 'Changelog, terms, policies, app version',
            onTap: () => _open(context, const AboutScreen()),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

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
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: ListTile(
              leading: Icon(icon, color: iconColor ?? AppTheme.primary),
              title: Text(
                title,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.textSecondary.withValues(alpha: 0.6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
