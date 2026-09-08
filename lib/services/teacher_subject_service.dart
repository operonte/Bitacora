import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Qué asignaturas dice cada docente que imparte, por carrera. Autoservicio:
/// no hace falta admin, el propio docente elige — el servidor exige tener
/// rol docente en esa carrera (RPC set_teaching_subject/is_docente).
///
/// Sin caché local a propósito: se consulta poco (Configuración → Mis
/// asignaturas, o al subir material) y siempre con conexión igual.
class TeacherSubjectService {
  static SupabaseClient get _client => SupabaseService.client;

  static Future<List<String>> myTeachingSubjects(String careerId) async {
    final rows = await _client.rpc('get_my_teaching_subjects', params: {
      'p_career_id': careerId,
    });
    return (rows as List).map((r) => (r as Map)['subject'].toString()).toList();
  }

  static Future<void> setTeaching(String careerId, String subject, bool teaching) async {
    await _client.rpc('set_teaching_subject', params: {
      'p_career_id': careerId,
      'p_subject': subject,
      'p_teaching': teaching,
    });
  }
}
