import 'package:bitacora/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:bitacora/models/career_model.dart';
import 'package:bitacora/subject_model.dart';
import 'package:bitacora/utils/hive_box_helper.dart';
import 'career_firestore_service.dart';
import 'encryption_service.dart';

/// Servicio para gestión de carreras académicas.
///
/// Un usuario puede pertenecer a **varias** carreras/grupos a la vez. Las
/// membresías se guardan como una lista en Hive (`careers`) y una de ellas es
/// la carrera "activa" (`active_career_id`), usada para el título y como
/// destino por defecto de las tareas nuevas. Se mantiene compatibilidad con el
/// formato antiguo de una sola carrera (`selected_career`) vía migración.
class CareerService extends ChangeNotifier {
  static final CareerService _instance = CareerService._internal();
  factory CareerService() => _instance;
  CareerService._internal();

  Box? _careerBox;

  static const _careersKey = 'careers';
  static const _activeKey = 'active_career_id';
  static const _legacyKey = 'selected_career';

  /// Inicializa el servicio
  Future<void> initialize() async {
    _careerBox = await openHiveBoxSafelyUntyped('career_settings', cipher: EncryptionService.cipher);
    _migrateLegacyIfNeeded();
  }

  // ── Lectura ─────────────────────────────────────────────────────────

  /// Lista de carreras a las que pertenece el usuario.
  List<Career> getCareers() {
    if (_careerBox == null) {
      Logger.warning('CareerService no inicializado! Hive box es null', tag: 'CareerService');
      return [];
    }
    try {
      final raw = _careerBox?.get(_careersKey);
      if (raw is! List) return [];
      return raw
          .map((e) => _parseCareer(e))
          .whereType<Career>()
          .toList();
    } catch (e) {
      Logger.error('Error al obtener carreras desde Hive: $e', error: e, tag: 'CareerService');
      return [];
    }
  }

  /// Carrera activa (la usada para título y tareas nuevas). Devuelve la
  /// marcada como activa, o la primera de la lista, o null si no hay ninguna.
  Career? getSelectedCareer() {
    final careers = getCareers();
    if (careers.isEmpty) return null;
    final activeId = _careerBox?.get(_activeKey) as String?;
    if (activeId != null) {
      for (final c in careers) {
        if (c.id == activeId) return c;
      }
    }
    return careers.first;
  }

  /// Ids de todas las carreras del usuario.
  List<String> get careerIds => getCareers().map((c) => c.id).toList();

  /// Indica si el usuario pertenece a la carrera [careerId].
  bool isMember(String? careerId) =>
      careerId != null && careerIds.contains(careerId);

  /// True si una tarea con [careerId] debe mostrarse al usuario: las tareas
  /// sin carrera (personales antiguas) se muestran siempre; el resto solo si
  /// pertenece a esa carrera.
  bool matchesAnyCareer(String? careerId) =>
      careerId == null || careerId.isEmpty || isMember(careerId);

  // ── Escritura ───────────────────────────────────────────────────────

  /// Agrega una carrera (si no está ya) y la deja como activa.
  Future<void> addCareer(Career career) async {
    final careers = getCareers();
    final exists = careers.any((c) => c.id == career.id);
    if (!exists) {
      careers.add(career);
      await _careerBox?.put(_careersKey, careers.map((c) => c.toMap()).toList());
      Logger.info('Carrera agregada: ${career.name}');
    }
    await _careerBox?.put(_activeKey, career.id);
    notifyListeners();
  }

  /// Alias compatible: agregar/seleccionar una carrera.
  Future<void> saveSelectedCareer(Career career) => addCareer(career);

  /// Marca [careerId] como carrera activa.
  Future<void> setActiveCareer(String careerId) async {
    if (!isMember(careerId)) return;
    await _careerBox?.put(_activeKey, careerId);
    notifyListeners();
  }

  /// Quita una carrera de las membresías del usuario.
  Future<void> removeCareer(String careerId) async {
    final careers = getCareers()..removeWhere((c) => c.id == careerId);
    await _careerBox?.put(_careersKey, careers.map((c) => c.toMap()).toList());

    final activeId = _careerBox?.get(_activeKey) as String?;
    if (activeId == careerId) {
      if (careers.isNotEmpty) {
        await _careerBox?.put(_activeKey, careers.first.id);
      } else {
        await _careerBox?.delete(_activeKey);
      }
    }
    Logger.info('Carrera removida: $careerId');
    notifyListeners();
  }

  /// Carga las carreras creadas en el admin (Firestore) y las deja
  /// disponibles en [Careers.remote] para validar claves y resolver nombres.
  /// Best-effort: si falla (offline / sin sesión), no lanza.
  Future<void> loadRemoteCareers() async {
    try {
      Careers.remote = await CareerFirestoreService().fetchCustomCareers();
      Logger.info('Carreras remotas cargadas: ${Careers.remote.length}', tag: 'CareerService');
    } catch (e) {
      Logger.warning('No se pudieron cargar carreras remotas: $e', tag: 'CareerService');
    }
  }

  /// Valida clave de acceso
  Career? validateAccessKey(String accessKey) {
    return Careers.findByAccessKey(accessKey);
  }

  /// Nombre legible de la carrera [careerId]: primero entre las carreras del
  /// usuario (disponibles offline), luego entre todas las conocidas.
  String? careerNameFor(String? careerId) {
    if (careerId == null || careerId.isEmpty) return null;
    for (final c in getCareers()) {
      if (c.id == careerId) return c.name;
    }
    return Careers.findById(careerId)?.name;
  }

  /// Fuerza la recarga de materias desde el código actualizado para todas las
  /// carreras predefinidas a las que pertenece el usuario.
  Future<void> reloadCareerWithUpdatedSubjects() async {
    final careers = getCareers();
    if (careers.isEmpty) return;
    final updated = careers
        .map((c) => Careers.findByAccessKey(c.accessKey) ?? c)
        .toList();
    await _careerBox?.put(_careersKey, updated.map((c) => c.toMap()).toList());
    Logger.info('Carreras recargadas con materias actualizadas');
    notifyListeners();
  }

  /// Limpia TODAS las carreras (logout completo).
  Future<void> clearSelectedCareer() async {
    await _careerBox?.delete(_careersKey);
    await _careerBox?.delete(_activeKey);
    await _careerBox?.delete(_legacyKey);
    Logger.info('Carreras limpiadas');
    notifyListeners();
  }

  // ── Internos ────────────────────────────────────────────────────────

  /// Migra el formato antiguo de una sola carrera (`selected_career`) al nuevo
  /// formato de lista, si aún no se ha hecho.
  void _migrateLegacyIfNeeded() {
    if (_careerBox == null) return;
    final hasNew = _careerBox?.get(_careersKey) != null;
    final legacy = _careerBox?.get(_legacyKey);
    if (hasNew || legacy == null) return;
    try {
      final career = _parseCareer(legacy);
      if (career != null) {
        _careerBox?.put(_careersKey, [career.toMap()]);
        _careerBox?.put(_activeKey, career.id);
        Logger.info('Migrada carrera antigua "${career.name}" al nuevo formato', tag: 'CareerService');
      }
    } catch (e) {
      Logger.error('Error migrando carrera antigua: $e', error: e, tag: 'CareerService');
    }
  }

  /// Convierte un Map (de Hive) en un Career de forma defensiva.
  Career? _parseCareer(dynamic rawData) {
    try {
      late Map<String, dynamic> data;
      if (rawData is Map<String, dynamic>) {
        data = rawData;
      } else if (rawData is Map) {
        data = rawData.cast<String, dynamic>();
      } else {
        return null;
      }

      final subjectsList = List<dynamic>.from(data['predefinedSubjects'] as List);
      final subjects = subjectsList.map((s) {
        final subjectMap = s is Map<String, dynamic> ? s : (s as Map).cast<String, dynamic>();
        return Subject.fromMap(subjectMap);
      }).toList();

      return Career(
        id: data['id'],
        name: data['name'],
        accessKey: data['accessKey'],
        predefinedSubjects: subjects,
      );
    } catch (e) {
      Logger.error('Error parseando carrera desde Hive: $e', error: e, tag: 'CareerService');
      return null;
    }
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
