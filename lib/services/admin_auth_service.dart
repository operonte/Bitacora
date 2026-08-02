import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'supabase_service.dart';

/// Servicio de autenticación administrativa para operaciones protegidas.
///
/// El hash de la contraseña se guarda en la tabla `profiles` de Supabase
/// (columna `admin_password_hash`). Solo el propio usuario autenticado puede
/// leer y actualizar su fila (RLS).
///
/// ADVERTENCIA: esta verificación corre en el cliente, así que el hash de
/// respaldo (`_defaultAdminHash`) viaja compilado dentro de la app y puede
/// extraerse del instalador. El límite de intentos de abajo solo dificulta
/// probarlo repetidamente *desde la app*; no protege contra alguien que
/// extraiga el hash y lo intente romper offline. La protección real tiene
/// que venir del lado del servidor: las políticas RLS de Supabase para las
/// tablas que administra este panel (`careers`, materias, etc.) deben, por
/// su cuenta, restringir la escritura a usuarios realmente autorizados — no
/// asumir que si algo llegó hasta aquí es porque pasó por este check.
class AdminAuthService {
  static SupabaseClient get _client => SupabaseService.client;

  // Hash SHA-256 de respaldo de la contraseña máster.
  // Rotada el 2026-08-01: la clave anterior quedó expuesta en texto plano en
  // el historial de git (commits públicos entre 2026-05-31 y 2026-06-13).
  // La clave en texto plano NUNCA debe volver a un archivo versionado.
  static const _defaultAdminHash =
      '50f1d166455f9321436a0fbaf5fbab958b361a5cb5298979d744eecb9e568ace';

  // Límite de intentos fallidos antes de bloquear temporalmente.
  static const int _maxAttempts = 5;
  static const Duration _lockDuration = Duration(minutes: 15);
  static const _attemptsKey = 'admin_auth_failed_attempts';
  static const _lockUntilKey = 'admin_auth_lock_until_ms';

  /// Verifica si la contraseña ingresada coincide con la clave máster (hash)
  /// o con el hash guardado en Supabase para el usuario autenticado actual.
  /// Tras [_maxAttempts] fallos seguidos, bloquea nuevos intentos por
  /// [_lockDuration] (defensa básica contra prueba y error repetido desde
  /// la propia app; ver advertencia de la clase).
  static Future<bool> verifyPassword(String password) async {
    final prefs = await SharedPreferences.getInstance();

    if (await _isLocked(prefs)) {
      Logger.warning(
        'Acceso admin bloqueado temporalmente por demasiados intentos fallidos',
        tag: 'AdminAuth',
      );
      return false;
    }

    final isValid = await _checkPassword(password);

    if (isValid) {
      await prefs.remove(_attemptsKey);
      await prefs.remove(_lockUntilKey);
      return true;
    }

    await _registerFailedAttempt(prefs);
    return false;
  }

  static Future<bool> _isLocked(SharedPreferences prefs) async {
    final lockUntilMs = prefs.getInt(_lockUntilKey);
    if (lockUntilMs == null) return false;

    if (DateTime.now().millisecondsSinceEpoch < lockUntilMs) {
      return true;
    }

    // El bloqueo ya expiró: reiniciar contador para permitir nuevos intentos.
    await prefs.remove(_lockUntilKey);
    await prefs.remove(_attemptsKey);
    return false;
  }

  static Future<void> _registerFailedAttempt(SharedPreferences prefs) async {
    final attempts = (prefs.getInt(_attemptsKey) ?? 0) + 1;
    await prefs.setInt(_attemptsKey, attempts);

    if (attempts >= _maxAttempts) {
      final lockUntil = DateTime.now().add(_lockDuration);
      await prefs.setInt(_lockUntilKey, lockUntil.millisecondsSinceEpoch);
      Logger.warning(
        'Demasiados intentos fallidos de acceso admin: bloqueado ${_lockDuration.inMinutes} min',
        tag: 'AdminAuth',
      );
    }
  }

  static Future<bool> _checkPassword(String password) async {
    try {
      final inputHash = sha256.convert(utf8.encode(password)).toString();

      // 1. Verificación contra hash predeterminado de la clave máster
      if (inputHash == _defaultAdminHash) {
        return true;
      }

      // 2. Verificación de hash guardado en Supabase
      final user = _client.auth.currentUser;
      if (user == null) return false;

      final rows = await _client
          .from('profiles')
          .select('admin_password_hash')
          .eq('id', user.id)
          .limit(1);

      if (rows.isNotEmpty) {
        final storedHash = rows.first['admin_password_hash'] as String?;
        if (storedHash != null && storedHash.isNotEmpty) {
          return inputHash == storedHash;
        }
      }

      return false;
    } catch (e) {
      Logger.error(
        'Error verificando contraseña admin: $e',
        error: e,
        tag: 'AdminAuth',
      );
      return false;
    }
  }

  /// Guarda o actualiza el hash de la contraseña de admin del usuario actual.
  static Future<void> setPassword(String password) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final hash = sha256.convert(utf8.encode(password)).toString();
    await _client
        .from('profiles')
        .update({'admin_password_hash': hash})
        .eq('id', user.id);
  }
}
