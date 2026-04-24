import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static const String _defaultServerClientId =
      '257026329569-cishq79r99aia7mja8cud5j093dusqd4.apps.googleusercontent.com';
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: _defaultServerClientId,
  );

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize(
      serverClientId: _serverClientId,
    );
    _googleSignInInitialized = true;
  }

  /// Returns selected Google account email on success.
  /// Returns null when the user cancels the account picker.
  Future<String?> signInWithGoogle() async {
    try {
      await _ensureGoogleSignInInitialized();

      if (!_googleSignIn.supportsAuthenticate()) {
        throw Exception(
          'Google Sign-In is not supported on this platform/device.',
        );
      }
      
      // In google_sign_in 7.2.0+, use authenticate() for sign-in.
      final GoogleSignInAccount account = await _googleSignIn.authenticate(
        scopeHint: const [
          'email',
          'profile',
        ],
      );
      
      return account.email;
    } on GoogleSignInException catch (e) {
      debugPrint(
        'AuthService: Google SignIn Exception: code=${e.code}, '
        'description=${e.description}',
      );
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }
      throw Exception(_mapGoogleSignInException(e));
    } catch (e, stack) {
      debugPrint('AuthService: Unexpected Google Sign-In error: $e');
      debugPrint('AuthService: Stack trace: $stack');
      rethrow;
    }
  }

  String _mapGoogleSignInException(GoogleSignInException e) {
    final details = (e.description ?? '').trim();

    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
        return 'Google Sign-In is misconfigured. Verify package name, SHA-1, '
            'and OAuth client IDs in Firebase/Google Cloud.'
            '${details.isEmpty ? '' : ' Details: $details'}';
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Sign-In provider is unavailable or misconfigured on '
            'this device. Update Google Play services and retry.'
            '${details.isEmpty ? '' : ' Details: $details'}';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google Sign-In UI is unavailable. Ensure the app is in the '
            'foreground and try again.'
            '${details.isEmpty ? '' : ' Details: $details'}';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google Sign-In was interrupted. Please try again.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Google account mismatch detected. Sign out and try again.';
      case GoogleSignInExceptionCode.canceled:
      default:
        return details.isEmpty
            ? 'Google Sign-In failed due to an unknown error.'
            : 'Google Sign-In failed: $details';
    }
  }

  /// In a production decentralized app, this would call a central verification 
  /// authority that sends an email with a deep link back to the app.
  Future<void> sendVerificationEmail(String email) async {
    debugPrint('AuthService: Sending verification link to $email');
    await Future.delayed(const Duration(seconds: 1)); // Simulate network call
  }

  Future<void> signOut() async {
    await _ensureGoogleSignInInitialized();
    await _googleSignIn.signOut();
  }
}
