import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';

class SessionControlService {
  static final SessionControlService _instance = SessionControlService._internal();
  factory SessionControlService() => _instance;
  SessionControlService._internal();

  static const int maxSimultaneousSessions = 4;

  /// Registra la sesión actual y valida que no exceda las 4 sesiones activas.
  Future<bool> validateAndRegisterSession({
    required String deviceName,
    required String deviceId,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return true;

    try {
      // 1. Consultar sesiones activas del usuario
      final response = await Supabase.instance.client
          .from('active_sessions')
          .select()
          .eq('user_id', user.id);

      final List<dynamic> sessions = response as List<dynamic>;

      // 2. Verificar si el dispositivo actual ya está registrado
      final existingIndex = sessions.indexWhere((s) => s['device_id'] == deviceId);

      if (existingIndex != -1) {
        // Dispositivo ya registrado, actualizar último acceso
        await Supabase.instance.client
            .from('active_sessions')
            .update({'last_active': DateTime.now().toIso8601String()})
            .eq('id', sessions[existingIndex]['id']);
        return true;
      }

      // 3. Si hay 4 o más sesiones activas en otros dispositivos, denegar
      if (sessions.length >= maxSimultaneousSessions) {
        Logger.warning(
          'Límite de $maxSimultaneousSessions sesiones simultáneas alcanzado para usuario ${user.id}',
          tag: 'SessionControl',
        );
        return false;
      }

      // 4. Registrar la nueva sesión
      await Supabase.instance.client.from('active_sessions').insert({
        'user_id': user.id,
        'device_name': deviceName,
        'device_id': deviceId,
        'last_active': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      Logger.warning('No se pudo verificar sesiones (modo tolerante): $e', tag: 'SessionControl');
      return true; // En caso de fallo de red, se permite el acceso en modo tolerante
    }
  }

  /// Elimina el registro de sesión al cerrar sesión.
  Future<void> removeSession(String deviceId) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from('active_sessions')
          .delete()
          .eq('user_id', user.id)
          .eq('device_id', deviceId);
    } catch (e) {
      Logger.warning('Error removiendo sesión activa: $e', tag: 'SessionControl');
    }
  }
}
