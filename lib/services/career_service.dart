import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:bitacora/models/career_model.dart';

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
    print('✅ Carrera guardada: ${career.name}');
    notifyListeners();
  }
  
  /// Obtiene la carrera seleccionada
  Career? getSelectedCareer() {
    final data = _careerBox?.get('selected_career');
    if (data == null) return null;
    
    return Career(
      id: data['id'],
      name: data['name'],
      accessKey: data['accessKey'],
      predefinedSubjects: List<String>.from(data['predefinedSubjects']),
    );
  }
  
  /// Valida clave de acceso
  Career? validateAccessKey(String accessKey) {
    return Careers.findByAccessKey(accessKey);
  }
  
  /// Limpia carrera seleccionada (logout)
  Future<void> clearSelectedCareer() async {
    await _careerBox?.delete('selected_career');
    print('🧹 Carrera seleccionada limpiada');
    notifyListeners();
  }
  
  /// Cierra recursos
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
      'predefinedSubjects': predefinedSubjects,
    };
  }
}
