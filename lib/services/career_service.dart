import 'package:bitacora/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:bitacora/models/career_model.dart';
import 'package:bitacora/subject_model.dart';
import 'package:bitacora/utils/hive_box_helper.dart';
import 'encryption_service.dart';

/// Servicio para gestión de carreras académicas
class CareerService extends ChangeNotifier {
  static final CareerService _instance = CareerService._internal();
  factory CareerService() => _instance;
  CareerService._internal();

  Box? _careerBox;

  /// Inicializa el servicio
  Future<void> initialize() async {
    _careerBox = await openHiveBoxSafelyUntyped('career_settings', cipher: EncryptionService.cipher);
  }

  /// Guarda la carrera seleccionada
  Future<void> saveSelectedCareer(Career career) async {
    await _careerBox?.put('selected_career', career.toMap());
    Logger.info('Carrera guardada: ${career.name}');
    notifyListeners();
  }

  /// Obtiene la carrera seleccionada
  Career? getSelectedCareer() {
    if (_careerBox == null) {
      Logger.warning('CareerService no inicializado! Hive box es null', tag: 'CareerService');
      return null;
    }
    
    try {
      final rawData = _careerBox?.get('selected_career');
      if (rawData == null) {
        Logger.info('No hay carrera seleccionada en Hive', tag: 'CareerService');
        return null;
      }

      Logger.info('Tipo de rawData: ${rawData.runtimeType}', tag: 'CareerService');
      
      // Más defensivo: si ya es un Map, úsalo; si no, intenta convertir
      late Map<String, dynamic> data;
      if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else if (rawData is Map) {
        data = rawData.cast<String, dynamic>();
      } else {
        throw ArgumentError('rawData no es un Map, es ${rawData.runtimeType}');
      }
      
      Logger.info('Datos de carrera desde Hive: ${data.keys}', tag: 'CareerService');
      Logger.info('Carrera ID: ${data['id']}, accessKey: ${data['accessKey']}', tag: 'CareerService');
      
      final predefinedSubjectsRaw = data['predefinedSubjects'];
      Logger.info('Tipo de predefinedSubjects: ${predefinedSubjectsRaw.runtimeType}', tag: 'CareerService');
      
      final subjectsList = List<dynamic>.from(predefinedSubjectsRaw as List);
      Logger.info('Materias en carrera: ${subjectsList.length}', tag: 'CareerService');
      
      final subjects = subjectsList.map((s) {
        late Map<String, dynamic> subjectMap;
        if (s is Map<String, dynamic>) {
          subjectMap = s;
        } else if (s is Map) {
          subjectMap = s.cast<String, dynamic>();
        } else {
          throw ArgumentError('Subject no es un Map, es ${s.runtimeType}');
        }
        return Subject.fromMap(subjectMap);
      }).toList();

      return Career(
        id: data['id'],
        name: data['name'],
        accessKey: data['accessKey'],
        predefinedSubjects: subjects,
      );
    } catch (e) {
      Logger.error('Error al obtener carrera desde Hive: $e', error: e, tag: 'CareerService');
      return null;
    }
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
    super.dispose();
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
