import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/menu_settings_service.dart';
import '../../theme.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<MenuSettingsController>(context);
    final notifications = settings.notifications;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _SectionCard(
            title: 'General',
            children: [
              SwitchListTile(
                value: notifications.sound,
                onChanged: (value) {
                  settings.setNotifications(
                    notifications.copyWith(sound: value),
                  );
                },
                title: const Text('Overall sound'),
                subtitle: const Text('Master switch for all app sounds'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Chat Notifications',
            children: [
              SwitchListTile(
                value: notifications.chatMessages,
                onChanged: (value) {
                  settings.setNotifications(
                    notifications.copyWith(chatMessages: value),
                  );
                },
                title: const Text('Chat notification panel'),
                subtitle: const Text('Show chat notifications in notification panel'),
              ),
              SwitchListTile(
                value: notifications.broadcastChannel,
                onChanged: (value) {
                  settings.setNotifications(
                    notifications.copyWith(broadcastChannel: value),
                  );
                },
                title: const Text('Broadcast channel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Notification settings are saved automatically.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
            child: Text(
              title,
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
