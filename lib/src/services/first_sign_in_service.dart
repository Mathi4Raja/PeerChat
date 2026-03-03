import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum FirstSignInMethod {
  google,
  email,
  guest,
}

extension FirstSignInMethodX on FirstSignInMethod {
  String get storageValue {
    switch (this) {
      case FirstSignInMethod.google:
        return 'google';
      case FirstSignInMethod.email:
        return 'email';
      case FirstSignInMethod.guest:
        return 'guest';
    }
  }
}

class FirstSignInDecision {
  final bool shouldShowChoice;
  final bool internetAvailable;
  final bool autoGuestSelected;

  const FirstSignInDecision({
    required this.shouldShowChoice,
    required this.internetAvailable,
    required this.autoGuestSelected,
  });
}

class FirstSignInService {
  static const String _completeKey = 'first_sign_in_complete_v1';
  static const String _methodKey = 'first_sign_in_method_v1';
  static const String _emailKey = 'first_sign_in_email_v1';
  static const String _timestampKey = 'first_sign_in_completed_at_ms_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<FirstSignInDecision> evaluateFirstSignIn() async {
    final completed = await _isCompleted();
    if (completed) {
      return const FirstSignInDecision(
        shouldShowChoice: false,
        internetAvailable: false,
        autoGuestSelected: false,
      );
    }

    final online = await _hasInternet();
    if (!online) {
      await complete(
        method: FirstSignInMethod.guest,
      );
      return const FirstSignInDecision(
        shouldShowChoice: false,
        internetAvailable: false,
        autoGuestSelected: true,
      );
    }

    return const FirstSignInDecision(
      shouldShowChoice: true,
      internetAvailable: true,
      autoGuestSelected: false,
    );
  }

  Future<void> complete({
    required FirstSignInMethod method,
    String? email,
  }) async {
    await _storage.write(key: _completeKey, value: 'true');
    await _storage.write(key: _methodKey, value: method.storageValue);
    await _storage.write(
      key: _timestampKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    if (email != null && email.trim().isNotEmpty) {
      await _storage.write(key: _emailKey, value: email.trim());
    } else {
      await _storage.delete(key: _emailKey);
    }
  }

  Future<bool> _isCompleted() async {
    final value = await _storage.read(key: _completeKey);
    return value == 'true';
  }

  Future<bool> _hasInternet() async {
    try {
      final lookup = await InternetAddress.lookup('dns.google').timeout(
        const Duration(seconds: 3),
      );
      if (lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final socket = await Socket.connect(
        '8.8.8.8',
        53,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
