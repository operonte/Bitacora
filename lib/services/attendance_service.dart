import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/hive_box_helper.dart';
import '../utils/logger.dart';
import 'encryption_service.dart';
import 'supabase_service.dart';

/// Asistencia por clase (carrera + asignatura + fecha), con caché local.
///
/// A diferencia de las demás pantallas docentes, esta sí necesita funcionar
/// sin conexión: pasar lista en una sala sin wifi es el caso normal, no la
/// excepción — es justo lo que iDoceo y Additio (las apps de referencia del
/// gremio) resuelven de entrada. El roster (nombres) solo se puede traer
/// online la primera vez; una vez en caché, se puede seguir marcando offline
/// y los cambios quedan pendientes hasta la próxima vez que la pantalla se
/// abra con conexión.
class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  SupabaseClient get _client => SupabaseService.client;

  static const List<String> statuses = [
    'presente',
    'tarde',
    'ausente',
    'justificado',
  ];

  Box? _box;
  static const _boxName = 'attendance_box';

  Future<void> init() async {
    _box = await openHiveBoxSafelyUntyped(_boxName, cipher: EncryptionService.cipher);
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _cacheKey(String careerId, String subject, DateTime classDate) =>
      '$careerId|$subject|${_dateOnly(classDate)}';

  /// Roster con nombres y estado. Si hay red, reintenta primero lo pendiente
  /// y trae la versión fresca del servidor (reaplicando encima lo que no se
  /// haya podido confirmar). Sin red, devuelve la última copia guardada.
  Future<List<Map<String, dynamic>>> getRoster(
    String careerId,
    String subject,
    DateTime classDate,
  ) async {
    final cacheKey = _cacheKey(careerId, subject, classDate);
    final stillPending = await _flushPending(careerId, subject, classDate);

    try {
      final rows = await _client.rpc('get_attendance_roster', params: {
        'p_career_id': careerId,
        'p_subject': subject,
        'p_class_date': _dateOnly(classDate),
      });

      final list = (rows as List)
          .map((r) => <String, dynamic>{
                ...Map<String, dynamic>.from(r as Map),
                'pending': false,
              })
          .toList();

      for (final entry in stillPending.entries) {
        final idx = list.indexWhere((r) => r['user_id'].toString() == entry.key);
        if (idx >= 0) {
          list[idx] = {...list[idx], 'status': entry.value, 'pending': true};
        }
      }

      await _box?.put(cacheKey, {'rows': list});
      return list;
    } catch (e) {
      final cached = _readCache(cacheKey);
      if (cached != null) {
        Logger.warning('Sin conexión, usando asistencia guardada', tag: 'AttendanceService');
        return cached;
      }
      rethrow;
    }
  }

  /// Marca un estado. Devuelve true si quedó confirmado en el servidor,
  /// false si quedó guardado localmente para reintentar después.
  Future<bool> setStatus(
    String careerId,
    String subject,
    DateTime classDate,
    String userId,
    String status,
  ) async {
    final cacheKey = _cacheKey(careerId, subject, classDate);
    await _setCacheRowStatus(cacheKey, userId, status, pending: true);
    try {
      await _client.rpc('set_attendance', params: {
        'p_career_id': careerId,
        'p_subject': subject,
        'p_class_date': _dateOnly(classDate),
        'p_user_id': userId,
        'p_status': status,
      });
      await _setCacheRowStatus(cacheKey, userId, status, pending: false);
      return true;
    } catch (e) {
      Logger.warning(
        'Sin conexión al marcar asistencia, queda pendiente de sincronizar',
        error: e,
        tag: 'AttendanceService',
      );
      return false;
    }
  }

  /// Reintenta las filas marcadas `pending` para esta clase. Devuelve las
  /// que siguen sin poder confirmarse (por ejemplo, si seguimos sin red).
  Future<Map<String, String>> _flushPending(
    String careerId,
    String subject,
    DateTime classDate,
  ) async {
    final cacheKey = _cacheKey(careerId, subject, classDate);
    final cached = _box?.get(cacheKey) as Map?;
    if (cached == null) return {};

    final rows = List<Map>.from((cached['rows'] as List?) ?? []);
    final stillPending = <String, String>{};

    for (final row in rows) {
      if (row['pending'] != true) continue;
      final uid = row['user_id'].toString();
      final status = row['status'].toString();
      try {
        await _client.rpc('set_attendance', params: {
          'p_career_id': careerId,
          'p_subject': subject,
          'p_class_date': _dateOnly(classDate),
          'p_user_id': uid,
          'p_status': status,
        });
      } catch (_) {
        stillPending[uid] = status;
      }
    }
    return stillPending;
  }

  List<Map<String, dynamic>>? _readCache(String cacheKey) {
    final cached = _box?.get(cacheKey) as Map?;
    if (cached == null) return null;
    final rows = cached['rows'] as List?;
    if (rows == null) return null;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> _setCacheRowStatus(
    String cacheKey,
    String userId,
    String status, {
    required bool pending,
  }) async {
    final cached = _box?.get(cacheKey) as Map?;
    final rows = cached != null ? List<Map>.from(cached['rows'] as List? ?? []) : <Map>[];
    final idx = rows.indexWhere((r) => r['user_id'].toString() == userId);
    final updated = {'user_id': userId, 'status': status, 'pending': pending};
    if (idx >= 0) {
      rows[idx] = {...rows[idx], ...updated};
    } else {
      rows.add(updated);
    }
    await _box?.put(cacheKey, {'rows': rows});
  }
}
