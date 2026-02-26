import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  bool _direct = true;
  bool _mesh = true;
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
                value: _direct,
                onChanged: (value) => setState(() => _direct = value),
                title: const Text('Direct chats'),
              ),
              SwitchListTile(
                value: _mesh,
                onChanged: (value) => setState(() => _mesh = value),
                title: const Text('Mesh chats'),
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
