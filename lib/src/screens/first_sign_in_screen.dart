import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/first_sign_in_service.dart';
import '../theme.dart';

class FirstSignInScreen extends StatefulWidget {
  final Future<void> Function(FirstSignInMethod method, {String? email})
      onComplete;

  const FirstSignInScreen({
    super.key,
    required this.onComplete,
  });

  @override
  State<FirstSignInScreen> createState() => _FirstSignInScreenState();
}

class _FirstSignInScreenState extends State<FirstSignInScreen> {
  final AuthService _authService = AuthService();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  bool _submitting = false;
  bool _verificationSent = false;
  final TextEditingController _emailController = TextEditingController();
  String? _emailError;
  String? _googleError;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      if (uri.scheme == 'peerchat' && uri.host == 'verify') {
        final email = uri.queryParameters['email'];
        if (email != null && _verificationSent) {
          _completeVerification(email);
        }
      }
    });
  }

  Future<void> _completeVerification(String email) async {
    setState(() => _submitting = true);
    await widget.onComplete(FirstSignInMethod.email, email: email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _submitGuest() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    await widget.onComplete(FirstSignInMethod.guest);
  }

  Future<void> _submitGoogle() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _googleError = null;
    });
    try {
      final googleEmail = await _authService.signInWithGoogle();
      if (!mounted) return;
      if (googleEmail == null) {
        setState(() {
          _submitting = false;
          _googleError = 'Google sign in cancelled';
        });
        return;
      }
      await widget.onComplete(
        FirstSignInMethod.google,
        email: googleEmail,
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('FirstSignInScreen: Google Sign-In error: $e');
      final raw = e.toString();
      final message = raw.startsWith('Exception: ')
          ? raw.substring('Exception: '.length)
          : raw.startsWith('StateError: ')
              ? raw.substring('StateError: '.length)
              : 'Google sign in failed: $raw';
      setState(() {
        _submitting = false;
        _googleError = message;
      });
    }
  }

  Future<void> _submitEmail() async {
    if (_submitting) return;
    final email = _emailController.text.trim();
    
    final emailErr = _validateEmail(email);
    if (emailErr != null) {
      setState(() => _emailError = emailErr);
      return;
    }

    setState(() {
      _submitting = true;
      _emailError = null;
    });

    try {
      await _authService.sendVerificationEmail(email);
      
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _verificationSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _emailError = 'Error: $e';
      });
    }
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Email is required';
    final regex =
        RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');
    if (!regex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                decoration: AppTheme.glassCard(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/image.png',
                          height: 80,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: AppTheme.primaryGradient,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Icon(Icons.shield,
                                size: 40, color: AppTheme.bgDeep),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Secure Mesh Messaging',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your privacy is our priority. Connect securely using your preferred method.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submitGoogle,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.account_circle_rounded),
                        label: Text(
                          'Sign in with Google',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    if (_googleError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _googleError!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'OR',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!_verificationSent) ...[
                      TextField(
                        controller: _emailController,
                        enabled: !_submitting,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submitEmail(),
                        onChanged: (_) {
                          if (_emailError == null) return;
                          setState(() {
                            _emailError = null;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'name@example.com',
                          errorText: _emailError,
                          prefixIcon: const Icon(Icons.alternate_email_rounded),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton(
                        onPressed: _submitting ? null : _submitEmail,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Send Verification Link',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.mark_email_read_rounded,
                              size: 48,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Verification Link Sent!',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'We sent a link to ${_emailController.text}.\nClick it to verify your identity and continue.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextButton(
                              onPressed: () => setState(() => _verificationSent = false),
                              child: const Text('Change Email'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _submitting ? null : _submitGuest,
                      child: Text(
                        'Continue as Guest',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 18,
                            color: AppTheme.primary.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'All messages are end-to-end encrypted. Sign-in is only used for identity verification.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_submitting) ...[
                      const SizedBox(height: 20),
                      const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

