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
  bool _submitting = false;
  final TextEditingController _emailController = TextEditingController();
  String? _emailError;
  String? _googleError;

  @override
  void dispose() {
    _emailController.dispose();
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
      setState(() {
        _submitting = false;
        _googleError = 'Google sign in failed: $e';
      });
    }
  }

  Future<void> _submitEmail() async {
    if (_submitting) return;
    final email = _emailController.text.trim();
    final error = _validateEmail(email);
    if (error != null) {
      setState(() {
        _emailError = error;
      });
      return;
    }
    setState(() => _submitting = true);
    _emailError = null;
    await widget.onComplete(FirstSignInMethod.email, email: email);
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
                    Text(
                      'Welcome to PeerChat Secure',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Internet is available. Choose your first sign-in method.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submitGoogle,
                      icon: const Icon(Icons.account_circle_rounded),
                      label: const Text('Google'),
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
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailController,
                      enabled: !_submitting,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (_emailError == null) return;
                        setState(() {
                          _emailError = null;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Email Sign In',
                        hintText: 'name@example.com',
                        errorText: _emailError,
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _submitting ? null : _submitEmail,
                      child: const Text('Continue with Email'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _submitting ? null : _submitGuest,
                      child: const Text('Continue as Guest'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'This prompt appears only on first sign in.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    if (_submitting) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
