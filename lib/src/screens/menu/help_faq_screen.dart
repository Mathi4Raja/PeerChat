import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';

class HelpFaqScreen extends StatelessWidget {
  const HelpFaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Help (FAQ)',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        children: const [
          _FaqItem(
            question: 'How does chat delivery work?',
            answer:
                'All chat messages use mesh routing. If a peer is connected, messages move immediately; otherwise they queue and relay through available peers.',
          ),
          _FaqItem(
            question: 'What is emergency broadcast?',
            answer:
                'Emergency broadcast sends signed messages to nearby peers in a public channel. It is not end-to-end encrypted.',
          ),
          _FaqItem(
            question: 'Can I use the app offline?',
            answer:
                'Yes. The app is designed for local peer-to-peer communication and can function without internet connectivity.',
          ),
        ],
      ),
    );
  }
}

class _FaqItem extends StatelessWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ExpansionTile(
        title: Text(
          question,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          Text(
            answer,
            style: GoogleFonts.inter(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

