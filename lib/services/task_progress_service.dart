import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive/hive.dart';
import '../utils/hive_box_helper.dart';
import '../utils/logger.dart';
import 'local_cache_service.dart';

/// Guarda el progreso personal (completada / enviada) por tarea y usuario.
/// Esto permite que tareas compartidas tengan estado independiente por alumno.
///
/// El progreso se cachea localmente en Hive (lectura instantánea, soporte
/// offline) y se sincroniza con Firestore (`userProgress/{uid}/tasks`) para
/// que el mismo usuario vea el mismo estado en todos sus dispositivos.
class TaskProgressService {
  static final TaskProgressService _instance =
      TaskProgressService._internal();
  factory TaskProgressService() => _instance;
  TaskProgressService._internal() : _firestoreOverride = null, _cache = LocalCacheService();

  /// Constructor para testing (inyección de dependencias)
  TaskProgressService.test({
    required FirebaseFirestore firestore,
    LocalCacheService? cache,
  }) : _firestoreOverride = firestore,
       _cache = cache ?? LocalCacheService();

  final FirebaseFirestore? _firestoreOverride;
  final LocalCacheService _cache;

  /// Instancia de Firestore obtenida de forma diferida: en el constructor
  /// singleton, `Firebase.app()` puede no estar listo todavía (ej. en tests
  /// que no inicializan Firebase y no usan progreso remoto).
  FirebaseFirestore get _firestore =>
      _firestoreOverride ??
      FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'dtbitacora');

  Box? _box;
  static const _boxName = 'task_progress';

  Future<void> initialize() async {
    _box = await openHiveBoxSafelyUntyped(_boxName);
  }

  String _key(String userId, String taskId) => '$userId:$taskId';

  CollectionReference _collection(String userId) => _firestore
      .collection('userProgress')
      .doc(userId)
      .collection('tasks');

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

  int _updatedAtOf(Map raw) => raw['updatedAt'] as int? ?? 0;

  /// Guarda el progreso personal para una tarea, en caché local y Firestore.
  Future<void> setProgress(
    String userId,
    String taskId, {
    required bool isCompleted,
    required bool isSubmitted,
  }) async {
    final updatedAt = DateTime.now().millisecondsSinceEpoch;
    await _box?.put(_key(userId, taskId), {
      'isCompleted': isCompleted,
      'isSubmitted': isSubmitted,
      'updatedAt': updatedAt,
    });
    Logger.info(
      'Progreso guardado: $taskId → completada=$isCompleted enviada=$isSubmitted',
      tag: 'TaskProgress',
    );

    try {
      await pushProgress(userId, taskId);
    } catch (e) {
      Logger.warning(
        'Error guardando progreso en Firebase, marcando para sync',
        error: e,
        tag: 'TaskProgress',
      );
      await _cache.markPendingSync('progress', _key(userId, taskId), 'update');
    }
  }

  /// Sube a Firestore el progreso guardado localmente para [taskId].
  /// Lanza si la escritura falla (usado por [SyncService] para reintentos).
  Future<void> pushProgress(String userId, String taskId) async {
    final raw = _box?.get(_key(userId, taskId));
    if (raw == null) return;
    final localRaw = Map<String, dynamic>.from(raw as Map);
    await _collection(userId).doc(taskId).set({
      'isCompleted': localRaw['isCompleted'] as bool? ?? false,
      'isSubmitted': localRaw['isSubmitted'] as bool? ?? false,
      'updatedAt': _updatedAtOf(localRaw),
    });
  }

  /// Reconcilia el progreso local (Hive) con Firestore para [userId].
  ///
  /// Usa "last-write-wins" según `updatedAt`: si una entrada local no
  /// existe en Firestore o es más reciente, se sube; si una entrada remota
  /// no existe localmente o es más reciente, se guarda en Hive.
  Future<void> syncProgress(String userId) async {
    if (_box == null) return;

    Map<String, dynamic> remoteEntries = {};
    try {
      final snapshot = await _collection(userId).get();
      for (final doc in snapshot.docs) {
        remoteEntries[doc.id] = doc.data();
      }
    } catch (e) {
      Logger.warning(
        'Error obteniendo progreso remoto, se omite sincronización',
        error: e,
        tag: 'TaskProgress',
      );
      return;
    }

    final prefix = '$userId:';
    final localKeys = (_box!.keys)
        .whereType<String>()
        .where((k) => k.startsWith(prefix));

    // Local -> remoto: subir entradas sin equivalente remoto o más nuevas.
    for (final key in localKeys) {
      final taskId = key.substring(prefix.length);
      final localRaw = Map<String, dynamic>.from(_box!.get(key) as Map);
      final remoteRaw = remoteEntries[taskId];

      if (remoteRaw == null ||
          _updatedAtOf(localRaw) > _updatedAtOf(remoteRaw)) {
        try {
          await pushProgress(userId, taskId);
        } catch (e) {
          Logger.warning(
            'Error subiendo progreso de $taskId',
            error: e,
            tag: 'TaskProgress',
          );
        }
      }
    }

    // Remoto -> local: descargar entradas sin equivalente local o más nuevas.
    for (final entry in remoteEntries.entries) {
      final taskId = entry.key;
      final remoteRaw = Map<String, dynamic>.from(entry.value as Map);
      final key = _key(userId, taskId);
      final localRaw = _box!.get(key) as Map?;

      if (localRaw == null ||
          _updatedAtOf(remoteRaw) > _updatedAtOf(Map<String, dynamic>.from(localRaw))) {
        await _box!.put(key, {
          'isCompleted': remoteRaw['isCompleted'] as bool? ?? false,
          'isSubmitted': remoteRaw['isSubmitted'] as bool? ?? false,
          'updatedAt': _updatedAtOf(remoteRaw),
        });
      }
    }
  }

  /// Elimina el progreso de una tarea (al borrarla).
  Future<void> clearProgress(String userId, String taskId) async {
    await _box?.delete(_key(userId, taskId));
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }
}
