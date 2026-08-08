import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import 'supabase_service.dart';

/// Puerta del panel de administración. Exige dos cosas:
///
/// 1. Que la cuenta autenticada tenga `profiles.is_admin = TRUE`.
/// 2. Que quien la usa sepa su contraseña de administrador.
///
/// Antes había una sola contraseña, compartida y compilada dentro de cada APK
/// como un SHA-256 sin sal. Se extraía del instalador, se rompía fuera de
/// línea, y como la comparación ocurría en el cliente bastaba parchear la app
/// para saltarse hasta el límite de intentos. Cada filtración obligaba a
/// rotarla a mano y publicar una versión nueva.
///
/// Ahora nada de eso vive acá: el hash es bcrypt con sal, está en
/// `admin_credentials` —una tabla que no lee nadie— y la comparación la hace
/// Postgres en `verify_admin_password()`. La app solo manda lo que el usuario
/// escribió y recibe un sí o un no.
///
/// El flag por sí solo no abre nada y la contraseña por sí sola tampoco: son
/// dos condiciones, y las dos las evalúa el servidor.
class AdminAuthService {
  static SupabaseClient get _client => SupabaseService.client;

  /// Largo mínimo. Debe coincidir con la validación de `set_admin_password`,
  /// que es la que manda — ésta solo evita un viaje de ida y vuelta.
  static const int minPasswordLength = 8;

  /// Si el usuario autenticado es administrador, según el servidor.
  ///
  /// Devuelve false ante cualquier fallo (sin sesión, sin red, RPC caída): no
  /// poder confirmar que alguien es admin no es lo mismo que serlo.
  static Future<bool> isCurrentUserAdmin() async {
    return _rpcBool('is_admin');
  }

  /// Si este administrador ya definió su contraseña. Cuando no, la pantalla de
  /// acceso pide crearla en vez de pedirla.
  static Future<bool> hasPassword() async {
    return _rpcBool('admin_password_is_set');
  }

  /// Comprueba la contraseña contra el hash guardado en el servidor.
  ///
  /// A los 5 intentos fallidos el servidor bloquea 15 minutos y esto sigue
  /// devolviendo false — no hay forma de distinguir bloqueo de clave errada, y
  /// es a propósito.
  static Future<bool> verifyPassword(String password) async {
    if (password.isEmpty) return false;
    return _rpcBool('verify_admin_password', {'p_password': password});
  }

  /// Define o cambia la contraseña del administrador actual.
  ///
  /// Lanza si el servidor la rechaza (no es admin, o es muy corta), para que
  /// la pantalla pueda mostrar el motivo en vez de fallar en silencio.
  static Future<void> setPassword(String password) async {
    await _client.rpc('set_admin_password', params: {'p_password': password});
  }

  // ── Miembros y administradores ─────────────────────────────────────────
  //
  // Todo pasa por funciones SECURITY DEFINER que comprueban is_admin() antes
  // de hacer nada. No hay políticas nuevas sobre las tablas: quien se salte la
  // app y llame al API directo sigue sin poder leer perfiles ajenos.

  /// Quién pertenece a [careerId].
  static Future<List<AdminMember>> careerMembers(String careerId) async {
    final rows = await _client.rpc(
      'admin_list_career_members',
      params: {'p_career_id': careerId},
    ) as List;
    return rows
        .map((r) => AdminMember.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Qué se lleva por delante borrar [careerId]. `user_careers` borra en
  /// cascada, así que esto no es informativo: es la diferencia entre saber y
  /// no saber que vas a expulsar a todo el mundo.
  static Future<CareerImpact> careerImpact(String careerId) async {
    final rows = await _client.rpc(
      'admin_career_impact',
      params: {'p_career_id': careerId},
    ) as List;
    if (rows.isEmpty) return const CareerImpact(0, 0, 0, 0);
    final r = Map<String, dynamic>.from(rows.first as Map);
    return CareerImpact(
      (r['members'] as num?)?.toInt() ?? 0,
      (r['tasks'] as num?)?.toInt() ?? 0,
      (r['meetings'] as num?)?.toInt() ?? 0,
      (r['files'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> removeMember(String careerId, String userId) async {
    await _client.rpc('admin_remove_member', params: {
      'p_career_id': careerId,
      'p_user_id': userId,
    });
  }

  static Future<List<AdminMember>> admins() async {
    final rows = await _client.rpc('admin_list_admins') as List;
    return rows
        .map((r) => AdminMember.fromMap(
              {...Map<String, dynamic>.from(r as Map), 'is_admin': true},
            ))
        .toList();
  }

  /// Define la contraseña de OTRO administrador.
  ///
  /// Hace falta porque nombrar a alguien solo le pone el permiso: sin una
  /// contraseña, `verify_admin_password()` le devuelve false y queda con el
  /// permiso y sin puerta. Sirve además para reponérsela a quien la olvidó,
  /// que si no quedaba bloqueado para siempre.
  ///
  /// El servidor la rechaza si la cuenta no es administradora.
  static Future<void> resetPasswordFor(String userId, String password) async {
    await _client.rpc('admin_reset_password', params: {
      'p_user_id': userId,
      'p_password': password,
    });
  }

  /// Busca una cuenta por correo. Devuelve null si no existe.
  static Future<AdminMember?> findUser(String email) async {
    final rows = await _client.rpc(
      'admin_find_user',
      params: {'p_email': email},
    ) as List;
    if (rows.isEmpty) return null;
    return AdminMember.fromMap(Map<String, dynamic>.from(rows.first as Map));
  }

  /// Da o quita el permiso de administrador.
  ///
  /// El servidor rechaza quitárselo a uno mismo y dejar la instalación sin
  /// ningún administrador: sin eso, un clic dejaba el panel sin dueño y sin
  /// forma de recuperarlo salvo escribiendo SQL a mano.
  static Future<void> setAdmin(String userId, bool value) async {
    await _client.rpc('admin_set_admin', params: {
      'p_user_id': userId,
      'p_is_admin': value,
    });
  }

  static Future<bool> _rpcBool(String fn, [Map<String, dynamic>? params]) async {
    if (_client.auth.currentUser == null) return false;
    try {
      final result = await _client.rpc(fn, params: params);
      return result == true;
    } catch (e) {
      Logger.warning('Falló $fn: $e', tag: 'AdminAuth');
      return false;
    }
  }
}

/// Una persona vista desde el panel: la fila de `profiles` que las funciones
/// de administración devuelven.
class AdminMember {
  final String userId;
  final String? displayName;
  final String? email;
  final bool isAdmin;
  final DateTime? joinedAt;

  /// Solo en la lista de administradores: si además tiene contraseña. Sin
  /// ella el permiso no sirve de nada — no puede abrir el panel.
  final bool hasPassword;

  const AdminMember({
    required this.userId,
    this.displayName,
    this.email,
    this.isAdmin = false,
    this.joinedAt,
    this.hasPassword = false,
  });

  /// Nombre para mostrar, con el correo como respaldo: `display_name` es nulo
  /// en las cuentas que nunca lo definieron.
  String get label {
    final nombre = displayName?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    return email ?? 'Sin nombre';
  }

  factory AdminMember.fromMap(Map<String, dynamic> map) => AdminMember(
        userId: map['user_id'].toString(),
        displayName: map['display_name']?.toString(),
        email: map['email']?.toString(),
        isAdmin: map['is_admin'] == true,
        joinedAt: map['joined_at'] == null
            ? null
            : DateTime.tryParse(map['joined_at'].toString()),
        hasPassword: map['has_password'] == true,
      );
}

/// Qué contenido cuelga de una carrera. Se muestra antes de borrarla.
class CareerImpact {
  final int members;
  final int tasks;
  final int meetings;
  final int files;

  const CareerImpact(this.members, this.tasks, this.meetings, this.files);

  bool get isEmpty => members == 0 && tasks == 0 && meetings == 0 && files == 0;
}
