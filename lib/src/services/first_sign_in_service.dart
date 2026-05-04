import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum FirstSignInMethod {
  guest,
}

extension FirstSignInMethodX on FirstSignInMethod {
  String get storageValue {
    switch (this) {
      case FirstSignInMethod.guest:
        return 'guest';
    }
  }
}

class FirstSignInDecision {
  final bool shouldShowChoice;
  final bool autoGuestSelected;

  const FirstSignInDecision({
    required this.shouldShowChoice,
    required this.autoGuestSelected,
  });
}

class FirstSignInService {
  static const String _completeKey = 'first_sign_in_complete_v1';
  static const String _methodKey = 'first_sign_in_method_v1';
  static const String _timestampKey = 'first_sign_in_completed_at_ms_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<FirstSignInDecision> evaluateFirstSignIn() async {
    final completed = await _isCompleted();
    if (completed) {
      return const FirstSignInDecision(
        shouldShowChoice: false,
        autoGuestSelected: false,
      );
    }

    // Always show the welcome screen if not completed
    return const FirstSignInDecision(
      shouldShowChoice: true,
      autoGuestSelected: false,
    );
  }

  Future<void> complete({
    required FirstSignInMethod method,
  }) async {
    await _storage.write(key: _completeKey, value: 'true');
    await _storage.write(key: _methodKey, value: method.storageValue);
    await _storage.write(
      key: _timestampKey,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  Future<void> reset() async {
    await _storage.delete(key: _completeKey);
    await _storage.delete(key: _methodKey);
    await _storage.delete(key: _timestampKey);
  }

  Future<bool> _isCompleted() async {
    final value = await _storage.read(key: _completeKey);
    return value == 'true';
  }
}
