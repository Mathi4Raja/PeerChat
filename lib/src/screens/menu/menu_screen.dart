import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';
import 'about_screen.dart';
import 'account_settings_screen.dart';
import 'display_settings_screen.dart';
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
          _MenuTile(
            icon: Icons.person_rounded,
            title: 'Account',
            subtitle: 'Name and profile picture',
            onTap: () => _open(context, const AccountSettingsScreen()),
          ),
          _MenuTile(
            icon: Icons.palette_rounded,
            title: 'Display',
            subtitle: 'Language and theme',
            onTap: () => _open(context, const DisplaySettingsScreen()),
          ),
          _MenuTile(
            icon: Icons.notifications_active_rounded,
            title: 'Notifications',
            subtitle: 'Sound, vibration, direct/mesh/broadcast',
            onTap: () => _open(context, const NotificationSettingsScreen()),
          ),
          _MenuTile(
            icon: Icons.share_rounded,
            title: 'Share This App',
            subtitle: 'Download link and offline sharing',
            onTap: () => _open(context, const ShareAppScreen()),
          ),
          _MenuTile(
            icon: Icons.favorite_rounded,
            title: 'Support',
            subtitle: 'Donate and feedback',
            onTap: () => _open(context, const SupportScreen()),
          ),
          _MenuTile(
            icon: Icons.help_outline_rounded,
            title: 'Help (FAQ)',
            subtitle: 'Common questions and answers',
            onTap: () => _open(context, const HelpFaqScreen()),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
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
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuTile({
    required this.icon,
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
              leading: Icon(icon, color: AppTheme.primary),
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
