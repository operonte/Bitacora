import 'package:hive/hive.dart';
import '../utils/hive_box_helper.dart';
import '../utils/logger.dart';

/// Guarda el progreso personal (completada / enviada) por tarea y usuario.
/// Esto permite que tareas compartidas tengan estado independiente por alumno.
class TaskProgressService {
  static final TaskProgressService _instance = TaskProgressService._internal();
  factory TaskProgressService() => _instance;
  TaskProgressService._internal();

  Box? _box;
  static const _boxName = 'task_progress';

  Future<void> initialize() async {
    _box = await openHiveBoxSafelyUntyped(_boxName);
  }

  String _key(String userId, String taskId) => '$userId:$taskId';

  /// Obtiene el progreso personal para una tarea.
  /// Devuelve null si no hay registro (usar valores del modelo como fallback).
  Map<String, bool>? getProgress(String userId, String taskId) {
    final raw = _box?.get(_key(userId, taskId));
    if (raw == null) return null;
    return {
      'isCompleted': raw['isCompleted'] as bool? ?? false,
      'isSubmitted': raw['isSubmitted'] as bool? ?? false,
    };
  }

  /// Guarda el progreso personal para una tarea.
  Future<void> setProgress(
    String userId,
    String taskId, {
    required bool isCompleted,
    required bool isSubmitted,
  }) async {
    await _box?.put(_key(userId, taskId), {
      'isCompleted': isCompleted,
      'isSubmitted': isSubmitted,
    });
    Logger.info(
      'Progreso guardado: $taskId → completada=$isCompleted enviada=$isSubmitted',
      tag: 'TaskProgress',
    );
  }

  /// Elimina el progreso de una tarea (al borrarla).
  Future<void> clearProgress(String userId, String taskId) async {
    await _box?.delete(_key(userId, taskId));
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }
}
