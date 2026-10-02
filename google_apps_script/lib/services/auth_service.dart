import 'package:firebase_auth/firebase_auth.dart';

/// Authentication operations for Crypto Doctors Hub.
///
/// UI screens keep their existing validation, messages and navigation while
/// Firebase Auth calls live here so authentication can be expanded safely
/// without changing the locked app interface.
class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() {
    return _auth.signOut();
  }
}
