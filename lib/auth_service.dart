import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      print('Iniciando proceso de Google Sign-In...');
      
      if (kIsWeb) {
        // Web sign in flow
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(googleProvider);
      } else {
        // Mobile sign in flow
        print('Solicitando cuenta de Google...');
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        
        if (googleUser == null) {
          print('Usuario canceló el inicio de sesión');
          return null;
        }
        
        print('Obteniendo tokens de autenticación...');
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        
        print('Access token: ${googleAuth.accessToken != null ? 'OK' : 'NULL'}');
        print('ID token: ${googleAuth.idToken != null ? 'OK' : 'NULL'}');
        
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        
        print('Autenticando con Firebase...');
        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        print('Autenticación exitosa: ${userCredential.user?.email}');
        return userCredential;
      }
    } on FirebaseAuthException catch (e) {
      print('FirebaseAuthException: ${e.code} - ${e.message}');
      throw Exception('Error de autenticación: ${e.message}');
    } catch (e) {
      print('Error general en sign in: $e');
      throw Exception('Error al iniciar sesión: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  // Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;

  // Get user display name
  String? get userDisplayName => _auth.currentUser?.displayName;

  // Get user email
  String? get userEmail => _auth.currentUser?.email;

  // Get user photo URL
  String? get userPhotoURL => _auth.currentUser?.photoURL;
}
