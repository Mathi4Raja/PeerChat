import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../app_state.dart';
import '../../services/menu_settings_service.dart';
import '../../services/username_registry_service.dart';
import '../../theme.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late TextEditingController _usernameController;
  bool _isSaving = false;
  bool _isChecking = false;
  String? _savedMessage;
  String? _errorMessage;

  final UsernameRegistryService _registry = UsernameRegistryService();

  @override
  void initState() {
    super.initState();
    final controller = context.read<MenuSettingsController>();
    _usernameController = TextEditingController(text: controller.username ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUsername() async {
    final appState = context.read<AppState>();
    final menuCtrl = context.read<MenuSettingsController>();
    final email = appState.registeredEmail;
    final newName = _usernameController.text.trim();

    if (email == null) return; // guests blocked at UI level

    setState(() {
      _isSaving = true;
      _isChecking = true;
      _errorMessage = null;
      _savedMessage = null;
    });

    try {
      // 1. Check uniqueness (skip if clearing)
      if (newName.isNotEmpty) {
        final available = await _registry.isAvailable(newName, email);
        if (!available) {
          if (mounted) {
            setState(() {
              _errorMessage = '"$newName" is already taken. Choose another.';
              _isChecking = false;
              _isSaving = false;
            });
          }
          return;
        }
      }

      setState(() => _isChecking = false);

      // 2. Save locally
      await menuCtrl.setUsername(
        newName.isEmpty ? null : newName,
        generatedFallback: appState.displayName,
      );
      appState.setCustomUsername(newName.isEmpty ? null : newName);

      // 3. Register in Firestore
      if (newName.isNotEmpty) {
        await _registry.register(newName, email);
      } else {
        await _registry.release(email);
      }

      if (mounted) {
        setState(() => _savedMessage = 'Username updated');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _savedMessage = null);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to save: ${e.toString().split('\n').first}');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final menuCtrl = context.watch<MenuSettingsController>();

    final isGuest = appState.registeredEmail == null;
    final displayName = appState.displayName;
    final initials = appState.initials;
    final email = appState.registeredEmail;
    final publicKey = appState.publicKey ?? 'Generating...';
    final storedUsername = menuCtrl.username;

    return Scaffold(
      appBar: AppBar(
        title: Text('Identity', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [

          // ─── Identity Card ───
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.13),
                  AppTheme.accentPurple.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.16),
                  child: Text(initials,
                    style: GoogleFonts.inter(
                      fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                      if (email != null) ...[
                        const SizedBox(height: 2),
                        Text(email,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.accent.withValues(alpha: 0.9), fontWeight: FontWeight.w500)),
                      ],
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isGuest
                              ? AppTheme.textSecondary.withValues(alpha: 0.1)
                              : AppTheme.online.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isGuest ? 'Guest' : 'Authenticated',
                          style: GoogleFonts.inter(
                            fontSize: 9, fontWeight: FontWeight.w700,
                            color: isGuest ? AppTheme.textSecondary : AppTheme.online,
                            letterSpacing: 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ─── Username ───
          if (!isGuest) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.badge_rounded, size: 15, color: AppTheme.primary),
                    const SizedBox(width: 7),
                    Text('Username',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                    const Spacer(),
                    if (_isChecking)
                      const SizedBox(width: 12, height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ]),
                  const SizedBox(height: 3),
                  Text('Unique across all PeerChat users. Visible to nearby peers.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _usernameController,
                    maxLength: 32,
                    textInputAction: TextInputAction.done,
                    style: GoogleFonts.inter(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: email != null ? email.split('@').first : 'Enter a username',
                      counterText: '',
                      errorText: _errorMessage,
                      suffixIcon: _usernameController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear_rounded, size: 16, color: AppTheme.textSecondary),
                              onPressed: () { _usernameController.clear(); setState(() {}); })
                          : null,
                    ),
                    onChanged: (_) => setState(() { _errorMessage = null; }),
                    onSubmitted: (_) => _saveUsername(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveUsername,
                      icon: _isSaving
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(_isChecking ? 'Checking…' : _isSaving ? 'Saving…' : 'Save Username'),
                    ),
                  ),
                  if (_savedMessage != null) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      const Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.online),
                      const SizedBox(width: 5),
                      Text(_savedMessage!,
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.online, fontWeight: FontWeight.w600)),
                    ]),
                  ],
                  if (storedUsername != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () async { _usernameController.clear(); await _saveUsername(); },
                      icon: Icon(Icons.restore_rounded, size: 13, color: AppTheme.textSecondary),
                      label: Text('Reset to generated name',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.08)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Guest users have a deterministic name generated from their cryptographic key. '
                    'Sign in with Google or email to set a custom username visible to nearby peers.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.5)),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ─── Public Key ───
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.key_rounded, size: 15, color: AppTheme.accent),
                const SizedBox(width: 7),
                Text('Cryptographic Identity Key',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              ]),
              const SizedBox(height: 3),
              Text('Your unique local-only P2P identity. Never shared with servers.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.4)),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: publicKey == 'Generating...' ? null : () {
                  Clipboard.setData(ClipboardData(text: publicKey));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Key copied'), duration: Duration(seconds: 1)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: AppTheme.bgDeep, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(
                      child: Text(publicKey, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(fontSize: 9.5, color: AppTheme.textSecondary))),
                    const SizedBox(width: 6),
                    const Icon(Icons.copy_rounded, size: 13, color: AppTheme.accent),
                  ]),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
