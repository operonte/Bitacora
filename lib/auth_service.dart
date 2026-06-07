import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'services/local_cache_service.dart';
import 'utils/logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  static bool _persistenceConfigured = false;
  Stream<User?>? _userStream;

  AuthService() {
    _configurePersistence();
  }

  Future<void> _configurePersistence() async {
    if (!kIsWeb || _persistenceConfigured) return;
    try {
      await _auth.setPersistence(Persistence.LOCAL);
      _persistenceConfigured = true;
      Logger.auth('Persistencia configurada: LOCAL');
    } catch (e) {
      Logger.warning('Error configurando persistencia', error: e, tag: 'Auth');
    }
  }

  /// Stream estable para la UI. En web usa [idTokenChanges] porque restaura
  /// la sesión de forma más fiable tras un refresh que [authStateChanges].
  Stream<User?> get userStream {
    _userStream ??= kIsWeb ? _auth.idTokenChanges() : _auth.authStateChanges();
    return _userStream!;
  }

  Stream<User?> get authStateChanges => userStream;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      Logger.auth('Iniciando proceso de Google Sign-In');

      if (kIsWeb) {
        await _configurePersistence();
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();

        Logger.auth('Iniciando signInWithPopup con Firebase Auth');
        final UserCredential userCredential = await _auth.signInWithPopup(
          googleProvider,
        );
        Logger.auth('Autenticación exitosa: ${userCredential.user?.email}');
        return userCredential;
      } else {
        Logger.auth('Solicitando cuenta de Google');
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          Logger.auth('Usuario canceló el inicio de sesión');
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(
          credential,
        );
        Logger.auth('Autenticación exitosa: ${userCredential.user?.email}');
        return userCredential;
      }
    } on FirebaseAuthException catch (e) {
      Logger.error('FirebaseAuthException', error: e, tag: 'Auth');
      throw Exception('Error de autenticación: ${e.message}');
    } catch (e) {
      Logger.error('Error general en sign in', error: e, tag: 'Auth');
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  Future<void> signOut() async {
    try {
      await LocalCacheService().clearAllCache();
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      Logger.error('Error signing out', error: e, tag: 'Auth');
    }
  }

  bool get isSignedIn => _auth.currentUser != null;
  String? get userDisplayName => _auth.currentUser?.displayName;
  String? get userEmail => _auth.currentUser?.email;
  String? get userPhotoURL => _auth.currentUser?.photoURL;
}
