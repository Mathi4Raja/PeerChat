import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import '../../theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _sound = true;
  bool _vibration = true;
  bool _messages = true;
  bool _relayUpdates = true;
  bool _broadcast = true;

  @override
  Widget build(BuildContext context) {
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
                value: _sound,
                onChanged: (value) => setState(() => _sound = value),
                title: const Text('Sound'),
              ),
              SwitchListTile(
                value: _vibration,
                onChanged: (value) => setState(() => _vibration = value),
                title: const Text('Vibration'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SectionCard(
            title: 'Chat Notifications',
            children: [
              SwitchListTile(
                value: _messages,
                onChanged: (value) => setState(() => _messages = value),
                title: const Text('Chat messages'),
              ),
              SwitchListTile(
                value: _relayUpdates,
                onChanged: (value) => setState(() => _relayUpdates = value),
                title: const Text('Relay/queue updates'),
              ),
              SwitchListTile(
                value: _broadcast,
                onChanged: (value) => setState(() => _broadcast = value),
                title: const Text('Broadcast channel'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Notification settings UI only for now'),
                ),
              );
            },
            child: const Text('Save'),
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

