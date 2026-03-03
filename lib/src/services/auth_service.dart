import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const <String>[
      'email',
      'profile',
    ],
  );

  /// Returns selected Google account email on success.
  /// Returns null when the user cancels the account picker.
  Future<String?> signInWithGoogle() async {
    final account = await _googleSignIn.signIn();
    return account?.email;
  }
}
