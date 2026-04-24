import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Enforces global username uniqueness using a private Firestore collection.
///
/// Schema: `username_registry/{username}` → { email, updatedAt }
///
/// Rules (set in Firebase Console):
///   allow read, write: if request.auth != null;  // or restrict further
///
/// For PeerChat we treat this as a best-effort lock — it prevents
/// accidental duplicates but is not a hard security boundary.
class UsernameRegistryService {
  static const _collection = 'username_registry';

  final FirebaseFirestore _db;

  UsernameRegistryService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  /// Returns `true` if [username] is available or already owned by [email].
  Future<bool> isAvailable(String username, String email) async {
    try {
      final doc = await _db
          .collection(_collection)
          .doc(_normalize(username))
          .get();

      if (!doc.exists) return true;
      // Already owned by same email → still available for them
      return (doc.data()?['email'] as String?)?.toLowerCase() ==
          email.toLowerCase();
    } catch (e) {
      debugPrint('UsernameRegistry.isAvailable: $e');
      // Fail open — don't block the user if Firestore is unreachable
      return true;
    }
  }

  /// Reserves [username] for [email], releasing any previous registration
  /// for this email first.
  Future<void> register(String username, String email) async {
    try {
      final normalized = _normalize(username);

      // Release old entry if exists
      await _releaseOldUsername(email);

      await _db.collection(_collection).doc(normalized).set({
        'email': email.toLowerCase(),
        'username': username.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('UsernameRegistry: registered "$username" for $email');
    } catch (e) {
      debugPrint('UsernameRegistry.register: $e');
      rethrow;
    }
  }

  /// Removes the username registration for [email] if one exists.
  Future<void> release(String email) async {
    try {
      await _releaseOldUsername(email);
    } catch (e) {
      debugPrint('UsernameRegistry.release: $e');
    }
  }

  // ── Private ──────────────────────────────────────────────

  Future<void> _releaseOldUsername(String email) async {
    final query = await _db
        .collection(_collection)
        .where('email', isEqualTo: email.toLowerCase())
        .limit(1)
        .get();

    for (final doc in query.docs) {
      await doc.reference.delete();
    }
  }

  String _normalize(String username) =>
      username.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
}
