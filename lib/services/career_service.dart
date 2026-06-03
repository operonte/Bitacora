import 'package:bitacora/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:bitacora/models/career_model.dart';
import 'package:bitacora/subject_model.dart';

/// Servicio para gestión de carreras académicas
class CareerService extends ChangeNotifier {
  static final CareerService _instance = CareerService._internal();
  factory CareerService() => _instance;
  CareerService._internal();

  Box? _careerBox;

  /// Inicializa el servicio
  Future<void> initialize() async {
    _careerBox = await Hive.openBox('career_settings');
  }

  /// Guarda la carrera seleccionada
  Future<void> saveSelectedCareer(Career career) async {
    await _careerBox?.put('selected_career', career.toMap());
    Logger.info('Carrera guardada: ${career.name}');
    notifyListeners();
  }

  /// Obtiene la carrera seleccionada
  Career? getSelectedCareer() {
    final data = _careerBox?.get('selected_career');
    if (data == null) return null;

    final subjectsList = data['predefinedSubjects'] as List;
    final subjects = subjectsList
        .map((s) => Subject.fromMap(s as Map<String, dynamic>))
        .toList();

    return Career(
      id: data['id'],
      name: data['name'],
      accessKey: data['accessKey'],
      predefinedSubjects: subjects,
    );
  }

  /// Valida clave de acceso
  Career? validateAccessKey(String accessKey) {
    return Careers.findByAccessKey(accessKey);
  }

  /// Fuerza la recarga de materias desde el código actualizado
  /// Útil cuando se actualizan los nombres de profesores en career_model.dart
  Future<void> reloadCareerWithUpdatedSubjects() async {
    final career = getSelectedCareer();
    if (career != null) {
      // Obtener la carrera actualizada desde el código
      final updatedCareer = Careers.findByAccessKey(career.accessKey);
      if (updatedCareer != null) {
        await saveSelectedCareer(updatedCareer);
        Logger.info('Carrera recargada con materias actualizadas');
      }
    }
  }

  /// Limpia carrera seleccionada (logout)
  Future<void> clearSelectedCareer() async {
    await _careerBox?.delete('selected_career');
    Logger.info('Carrera seleccionada limpiada');
    notifyListeners();
  }

  /// Cierra recursos
  @override
  void dispose() {
    _careerBox?.close();
  }
}

/// Extension para convertir Career a Map
extension CareerMap on Career {
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'accessKey': accessKey,
      'predefinedSubjects': predefinedSubjects.map((s) => s.toMap()).toList(),
    };
  }
}
