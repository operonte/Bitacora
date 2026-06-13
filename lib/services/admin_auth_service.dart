import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';

/// Servicio de autenticación administrativa para operaciones protegidas.
///
/// El hash de la contraseña se guarda en Firestore (`admins/{uid}`), nunca
/// en el código fuente. Solo el propio usuario admin puede leer su doc.
class AdminAuthService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Verifica si la contraseña ingresada coincide con el hash guardado
  /// en Firestore para el usuario autenticado actual.
  static Future<bool> verifyPassword(String password) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final doc = await _firestore.collection('admins').doc(user.uid).get();
      if (!doc.exists) return false;

      final storedHash = doc.data()?['passwordHash'] as String?;
      if (storedHash == null) return false;

      final inputHash = sha256.convert(utf8.encode(password)).toString();
      return inputHash == storedHash;
    } catch (e) {
      Logger.error('Error verificando contraseña admin', error: e, tag: 'AdminAuth');
      return false;
    }
  }
}
