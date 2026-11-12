import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService._();

  static final instance = GoogleAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleSignInInitialization;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail({required String email}) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> _ensureGoogleReady() async {
    if (_googleSignInInitialization != null) {
      await _googleSignInInitialization;
      return;
    }

    try {
      _googleSignInInitialization = _googleSignIn.initialize();
      await _googleSignInInitialization;
    } on Exception catch (_) {
      _googleSignInInitialization = null;
      throw FirebaseAuthException(
        code: 'google-signin-not-ready',
        message:
            'Google Sign-In chưa sẵn sàng. Kiểm tra Firebase, google-services.json và cấu hình Google trong Authentication.',
      );
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      await _ensureGoogleReady();
      final account = await _googleSignIn.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message:
              'Google không trả về mã xác thực. Kiểm tra cấu hình OAuth trong Firebase.',
        );
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);
      return _auth.signInWithCredential(credential);
    } on FirebaseAuthException {
      rethrow;
    } on Exception catch (_) {
      throw FirebaseAuthException(
        code: 'google-signin-unavailable',
        message:
            'Không thể bắt đầu đăng nhập Google. Vui lòng kiểm tra cấu hình Firebase và Google Sign-In.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
    } on Exception {
      // Đăng xuất bị hủy/không sẵn sàng không nên làm treo app.
    }
  }
}
