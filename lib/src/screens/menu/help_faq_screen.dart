import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import '../../theme.dart';

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Help & FAQ', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemCount: _faqs.length,
        itemBuilder: (context, i) {
          final faq = _faqs[i];
          return _FaqTile(question: faq.q, answer: faq.a);
        },
      ),
    );
  }
}

class _FaqItem {
  final String q;
  final String a;
  const _FaqItem(this.q, this.a);
}

const _faqs = [
  _FaqItem(
    'What is PeerChat?',
    'PeerChat is a serverless, peer-to-peer encrypted messaging and file transfer app. '
    'It forms a temporary mesh network using Bluetooth Low Energy (BLE) and WiFi Direct — '
    'no servers, no central infrastructure, no data harvesting.',
  ),
  _FaqItem(
    'Does PeerChat require an internet connection?',
    'No. PeerChat works entirely offline. It uses BLE for peer discovery and small '
    'data packets, and WiFi Direct or WiFi Hotspot for high-speed file transfers. '
    'Two devices just need to be within Bluetooth or WiFi range of each other.',
  ),
  _FaqItem(
    'How does multi-hop mesh routing work?',
    'If device A can reach B, and B can reach C, a message from A to C hops through B. '
    'Each hop is independently encrypted — B can relay the packet without reading it. '
    'Messages can travel across multiple hops until they reach the destination.',
  ),
  _FaqItem(
    'Is my data secure?',
    'Yes. Every message is end-to-end encrypted (E2EE) using Sodium (libsodium) '
    'with X25519 key agreement and ChaCha20-Poly1305. Messages are digitally signed '
    'with Ed25519. Only the intended recipient can decrypt your messages.',
  ),
  _FaqItem(
    'How do I add a peer or start a chat?',
    'Tap the QR icon to scan another user\'s QR code, or let nearby discovery find '
    'devices automatically via BLE. Once a handshake completes, they appear in your '
    'Nearby Peers list and you can start chatting.',
  ),
  _FaqItem(
    'What happens if I uninstall the app?',
    'Your cryptographic key pair and all stored messages are permanently deleted from '
    'the device. There is no cloud backup. Peers who had you in their list will still '
    'see your entry, but you will appear offline until you reinstall and reconnect.',
  ),
  _FaqItem(
    'What is the Emergency Broadcast?',
    'Emergency Broadcast sends a high-priority message to every connected peer '
    'simultaneously, ignoring the normal routing table. The message propagates '
    'through the entire reachable mesh. Use it only for genuine emergencies.',
  ),
  _FaqItem(
    'How do I transfer files?',
    'Open a chat with a peer, tap the attachment icon (📎), and pick any file. '
    'Files transfer directly between devices over WiFi Direct — no cloud upload, '
    'no size limits beyond device storage. Large files use Native File Payloads '
    'for maximum throughput.',
  ),
];

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> with SingleTickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: _expanded
            ? AppTheme.primary.withValues(alpha: 0.06)
            : AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _expanded
              ? AppTheme.primary.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Text(
                  widget.answer,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                    height: 1.55,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
