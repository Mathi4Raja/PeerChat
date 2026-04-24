import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_state.dart';
import '../../theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final TextEditingController _feedbackController = TextEditingController();
  bool _isSending = false;
  String? _sendResult;
  bool _sendSuccess = false;

  static const String _donateUrl = 'https://peerchat.mathi.live/donateus';
  static const String _feedbackTo = 'mathi.raja.333@gmail.com';
  static const String _feedbackSubject = 'PeerChat-Feedback';

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _openDonate() async {
    final uri = Uri.parse(_donateUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open donation page')));
    }
  }

  Future<void> _sendFeedback(AppState appState) async {
    final body = _feedbackController.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write your feedback first')));
      return;
    }

    final email = appState.registeredEmail;
    if (email == null) return; // guests blocked at UI level

    setState(() { _isSending = true; _sendResult = null; });

    final uri = Uri(
      scheme: 'mailto',
      path: _feedbackTo,
      queryParameters: {
        'subject': _feedbackSubject,
        'body': body,
        'from': email,
      },
    );

    bool sent = false;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      sent = true;
      _feedbackController.clear();
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        _sendSuccess = sent;
        _sendResult = sent
            ? 'Mail app opened — review and send.'
            : 'Could not open mail app. Email $_feedbackTo directly.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isGuest = appState.registeredEmail == null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Support', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [

          // ─── Donate ───
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.pinkAccent.withValues(alpha: 0.06),
                  AppTheme.accentPurple.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.12)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.favorite_rounded, size: 14, color: Colors.pinkAccent),
                const SizedBox(width: 7),
                Text('Support Development',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              ]),
              const SizedBox(height: 4),
              Text(
                'PeerChat is free and open source. Every contribution funds ongoing development and decentralized research.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.5)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _openDonate,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.pinkAccent.withValues(alpha: 0.12),
                    foregroundColor: Colors.pinkAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.volunteer_activism_rounded, size: 16),
                  label: Text('Donate', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 12),

          // ─── Feedback ───
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppTheme.accent),
                const SizedBox(width: 7),
                Text('Send Feedback',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              ]),
              const SizedBox(height: 3),
              Text('Bug reports, ideas, or suggestions.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),

              if (isGuest) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgDeep, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.08)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.lock_outline_rounded, size: 14, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'Sign in with Google or email to send feedback.',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.4))),
                  ]),
                ),
              ] else ...[
                TextField(
                  controller: _feedbackController,
                  minLines: 4,
                  maxLines: 7,
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Describe a bug, request a feature, or share thoughts…',
                    alignLabelWithHint: true,
                  ),
                  onChanged: (_) { if (_sendResult != null) setState(() => _sendResult = null); },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSending ? null : () => _sendFeedback(appState),
                    icon: _isSending
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 14),
                    label: Text(_isSending ? 'Opening…' : 'Send via Mail App'),
                  ),
                ),
                if (_sendResult != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(
                      _sendSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      size: 13,
                      color: _sendSuccess ? AppTheme.online : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 5),
                    Expanded(child: Text(_sendResult!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: _sendSuccess ? AppTheme.online : Colors.orangeAccent,
                        fontWeight: FontWeight.w600))),
                  ]),
                ],
                const SizedBox(height: 6),
                Text('Opens your mail app pre-filled with subject and body.',
                  style: GoogleFonts.inter(
                    fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.55))),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
