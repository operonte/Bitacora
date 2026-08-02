import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'career_service.dart';
import '../models/career_model.dart';
import '../models/subject_model.dart';

/// Servicio de Supabase para gestión de carreras con soporte en tiempo real.
/// Supabase es la fuente primaria de verdad. Si la base de datos de Supabase
/// contiene carreras (o modificaciones a carreras predefinidas como Teología),
/// la versión de la nube prevalece.
class CareerSupabaseService {
  final SupabaseClient _client = SupabaseService.client;
  static const _table = 'careers';

  Career _careerFromRow(Map<String, dynamic> row) {
    final subjectsList = List.from(row['predefined_subjects'] as List<dynamic>? ?? []);
    final subjects = subjectsList
        .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
        .toList();
    return Career(
      id: row['id'] as String,
      name: row['name'] as String,
      accessKey: row['access_key'] as String,
      description: row['description'] as String?,
      predefinedSubjects: subjects,
    );
  }

  Map<String, dynamic> _careerToRow(Career career) {
    return {
      'id': career.id,
      'name': career.name,
      'access_key': career.accessKey,
      'description': career.description ?? '',
      'predefined_subjects': career.predefinedSubjects
          .map((s) => s.toMap())
          .toList(),
    };
  }

  /// Combina las carreras predefinidas con las de Supabase.
  /// La versión de Supabase siempre tiene prioridad.
  List<Career> _mergeCareers(List<Career> dbCareers) {
    final Map<String, Career> map = {};
    for (final c in Careers.predefined) {
      map[c.id] = c;
    }
    for (final c in dbCareers) {
      map[c.id] = c;
    }
    return map.values.toList();
  }

  /// Carga puntual de carreras remotas desde Supabase
  Future<List<Career>> fetchCustomCareers() async {
    final rows = await _client.from(_table).select();
    return rows.map((r) => _careerFromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Stream de carreras en tiempo real (Supabase como Fuente de la Verdad)
  Stream<List<Career>> getCareersStream() {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .map((rows) {
          final dbCareers = rows.map((r) => _careerFromRow(Map<String, dynamic>.from(r as Map))).toList();
          return _mergeCareers(dbCareers);
        })
        .handleError((error) async* {
          try {
            final dbCareers = await fetchCustomCareers();
            yield _mergeCareers(dbCareers);
          } catch (_) {
            yield Careers.predefined;
          }
        });
  }

  /// Stream de una carrera específica
  Stream<Career?> getCareerStream(String careerId) {
    return _client
        .from(_table)
        .stream(primaryKey: ['id'])
        .eq('id', careerId)
        .map((rows) {
          if (rows.isNotEmpty) {
            return _careerFromRow(Map<String, dynamic>.from(rows.first as Map));
          }
          return Careers.all.firstWhere(
            (c) => c.id == careerId,
            orElse: () => Careers.predefined.first,
          );
        })
        .handleError((error) async* {
          try {
            final rows = await _client.from(_table).select().eq('id', careerId);
            if (rows.isNotEmpty) {
              yield _careerFromRow(Map<String, dynamic>.from(rows.first as Map));
            } else {
              yield Careers.findById(careerId);
            }
          } catch (_) {
            yield Careers.findById(careerId);
          }
        });
  }

  Future<void> createCareer(Career career) async {
    final row = _careerToRow(career);
    await _client.from(_table).insert(row);
    await CareerService().loadRemoteCareers();
  }

  Future<List<Career>> getAllCareers() async {
    final dbCareers = await fetchCustomCareers();
    return _mergeCareers(dbCareers);
  }

  Future<Career?> getCareerById(String id) async {
    final rows = await _client.from(_table).select().eq('id', id);
    if (rows.isNotEmpty) return _careerFromRow(Map<String, dynamic>.from(rows.first as Map));
    return Careers.findById(id);
  }

  Future<void> updateCareer(Career career) async {
    final row = _careerToRow(career);
    await _client.from(_table).upsert(row, onConflict: 'id');
    await CareerService().loadRemoteCareers();
  }

  Future<void> deleteCareer(String careerId) async {
    await _client.from(_table).delete().eq('id', careerId);
    await CareerService().loadRemoteCareers();
  }

  /// Trae los datos editables de una carrera (nombre, clave, descripción y
  /// materias), usando Supabase si existe o la versión predefinida en código
  /// como base. Usado por los métodos que modifican la lista de materias.
  Future<_CareerMutableData> _fetchCareerMutableData(String careerId) async {
    final rows = await _client.from(_table).select().eq('id', careerId);

    if (rows.isNotEmpty) {
      final data = Map<String, dynamic>.from(rows.first as Map);
      final subjectsList = List.from(data['predefined_subjects'] as List<dynamic>? ?? []);
      return _CareerMutableData(
        careerName: data['name'] as String? ?? 'Carrera',
        accessKey: data['access_key'] as String? ?? '',
        description: data['description'] as String?,
        subjects: subjectsList
            .map((s) => Subject.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
    }

    final predefined = Careers.all.firstWhere(
      (c) => c.id == careerId,
      orElse: () => Careers.predefined.first,
    );
    return _CareerMutableData(
      careerName: predefined.name,
      accessKey: predefined.accessKey,
      description: predefined.description,
      subjects: List.from(predefined.predefinedSubjects),
    );
  }

  /// Persiste la carrera con la lista de materias ya modificada y refresca
  /// el estado local (remoto + predefinido con materias actualizadas).
  Future<void> _persistCareerSubjects(
    String careerId,
    _CareerMutableData data,
  ) async {
    await _client.from(_table).upsert({
      'id': careerId,
      'name': data.careerName,
      'access_key': data.accessKey,
      'description': data.description ?? '',
      'predefined_subjects': data.subjects.map((s) => s.toMap()).toList(),
    }, onConflict: 'id');

    await CareerService().loadRemoteCareers();
    await CareerService().reloadCareerWithUpdatedSubjects();
  }

  Future<void> addSubjectToCareer(String careerId, Subject subject) async {
    final data = await _fetchCareerMutableData(careerId);
    final idx = data.subjects.indexWhere(
      (s) => s.id == subject.id || s.name.toLowerCase() == subject.name.toLowerCase(),
    );
    if (idx == -1) {
      data.subjects.add(subject);
    } else {
      data.subjects[idx] = subject;
    }
    await _persistCareerSubjects(careerId, data);
  }

  Future<void> updateSubjectInCareer(String careerId, Subject updatedSubject) async {
    final data = await _fetchCareerMutableData(careerId);
    final idx = data.subjects.indexWhere(
      (s) => s.id == updatedSubject.id || s.name.toLowerCase() == updatedSubject.name.toLowerCase(),
    );
    if (idx != -1) {
      data.subjects[idx] = updatedSubject;
    } else {
      data.subjects.add(updatedSubject);
    }
    await _persistCareerSubjects(careerId, data);
  }

  Future<void> removeSubjectFromCareer(
    String careerId,
    String subjectId,
  ) async {
    final data = await _fetchCareerMutableData(careerId);
    data.subjects.removeWhere(
      (s) => s.id == subjectId || (subjectId.isNotEmpty && s.name.toLowerCase() == subjectId.toLowerCase()),
    );
    await _persistCareerSubjects(careerId, data);
  }
}

/// Datos editables de una carrera, usados como paso intermedio al agregar,
/// actualizar o quitar una materia.
class _CareerMutableData {
  final String careerName;
  final String accessKey;
  final String? description;
  final List<Subject> subjects;

  _CareerMutableData({
    required this.careerName,
    required this.accessKey,
    required this.description,
    required this.subjects,
  });
}
