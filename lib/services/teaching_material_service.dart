import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/teaching_material_model.dart';
import '../utils/logger.dart';
import 'career_service.dart';
import 'supabase_db_service.dart';

/// Material docente compartido por carrera (archivos o enlaces que un
/// profesor envía al curso). Mismo patrón que MeetingService/StudyFileService
/// (caché local en Hive + sincronización con Supabase), pero consultando por
/// las carreras del usuario en vez de por user_id, porque es contenido
/// compartido con todo el curso — no privado como los archivos personales.
class TeachingMaterialService extends ChangeNotifier {
  static final TeachingMaterialService _instance =
      TeachingMaterialService._internal();
  factory TeachingMaterialService() => _instance;
  TeachingMaterialService._internal();

  static const String _boxName = 'teaching_materials_box';
  Box? _box;

  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      Logger.info('TeachingMaterialService inicializado', tag: 'TeachingMaterialService');
    } catch (e) {
      Logger.error(
        'Error inicializando TeachingMaterialService: $e',
        error: e,
        tag: 'TeachingMaterialService',
      );
    }
  }

  /// Materiales en caché local, opcionalmente filtrados por carrera. Sin
  /// [careerId], devuelve los de todas las carreras a las que pertenece el
  /// usuario, más recientes primero.
  List<TeachingMaterial> getMaterials({String? careerId}) {
    if (_box == null) return [];
    try {
      final careerIds =
          careerId != null ? {careerId} : CareerService().careerIds.toSet();

      final materials = _box!.values
          .map((e) {
            if (e is Map) {
              return TeachingMaterial.fromMap(Map<String, dynamic>.from(e));
            }
            return null;
          })
          .whereType<TeachingMaterial>()
          .where((m) => careerIds.contains(m.careerId))
          .toList();

      materials.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return materials;
    } catch (e) {
      Logger.error('Error parseando material docente: $e', tag: 'TeachingMaterialService');
      return [];
    }
  }

  /// Publica un material nuevo para toda la carrera. Si falla el guardado
  /// remoto, lanza (no hay reintento offline para este contenido compartido
  /// — mejor que el usuario sepa que no se publicó, a que quede una copia
  /// "fantasma" solo local que sus compañeros nunca ven).
  Future<void> addMaterial(TeachingMaterial material) async {
    final id = material.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final toSave = TeachingMaterial.fromMap({...material.toMap(), 'id': id});

    await SupabaseDbService().registerCareerMemberships();
    await Supabase.instance.client.from('teaching_materials').insert(toSave.toMap());

    await _box?.put(id, toSave.toMap());
    notifyListeners();
  }

  /// Elimina un material (la política RLS en Supabase solo deja borrar al
  /// autor original, ver plan de implementación).
  Future<void> deleteMaterial(String id) async {
    await _box?.delete(id);
    try {
      await Supabase.instance.client.from('teaching_materials').delete().eq('id', id);
    } catch (e) {
      Logger.warning('No se pudo borrar material docente remoto: $e', tag: 'TeachingMaterialService');
    }
    notifyListeners();
  }

  /// Trae el material de todas las carreras del usuario desde Supabase y
  /// actualiza la caché local.
  Future<void> syncFromSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final careerIds = CareerService().careerIds;
    if (careerIds.isEmpty) return;

    try {
      await SupabaseDbService().registerCareerMemberships();

      final response = await Supabase.instance.client
          .from('teaching_materials')
          .select()
          .inFilter('career_id', careerIds)
          .order('created_at', ascending: false);

      for (final item in response) {
        final m = TeachingMaterial.fromMap(Map<String, dynamic>.from(item));
        if (m.id != null) {
          await _box?.put(m.id, m.toMap());
        }
      }
      notifyListeners();
    } catch (e) {
      Logger.warning('Falló sincronización de material docente: $e', tag: 'TeachingMaterialService');
    }
  }
}
