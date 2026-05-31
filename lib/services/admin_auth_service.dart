/// Servicio de autenticación administrativa para operaciones protegidas
class AdminAuthService {
  static const String _adminPassword = 'operonte23';

  /// Verifica si la contraseña es correcta
  static bool verifyPassword(String password) {
    return password == _adminPassword;
  }

  /// Solicita contraseña al usuario y verifica
  static Future<bool> requestPasswordVerification() async {
    // Este método se implementará en la UI para mostrar un diálogo
    // y verificar la contraseña
    return false;
  }
}
