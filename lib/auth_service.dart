import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'services/local_cache_service.dart';
import 'utils/logger.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  AuthService() {
    _configurePersistence();
  }

  Future<void> _configurePersistence() async {
    try {
      // En web, Firebase Auth usa localStorage por defecto
      // Aseguramos que la persistencia esté habilitada
      await _auth.setPersistence(Persistence.LOCAL);
      Logger.auth('Persistencia configurada: LOCAL');
    } catch (e) {
      Logger.warning('Error configurando persistencia', error: e, tag: 'Auth');
    }
  }

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential?> signInWithGoogle() async {
    try {
      Logger.auth('Iniciando proceso de Google Sign-In');

      if (kIsWeb) {
        // En web, usar Firebase Auth con signInWithPopup
        // Esto detecta automáticamente cuentas existentes en el navegador
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.setCustomParameters({'prompt': 'select_account'});

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
