import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive/hive.dart';
import '../utils/hive_box_helper.dart';
import '../utils/logger.dart';
import 'supabase_service.dart';
import 'encryption_service.dart';
import 'local_cache_service.dart';

/// Guarda el progreso personal (completada / enviada) por tarea y usuario.
/// Equivale al antiguo TaskProgressService pero usando Supabase en lugar de Firestore.
///
/// Tabla Supabase: task_progress (user_id, task_id, is_completed, is_submitted, updated_at)
class TaskProgressService {
  static final TaskProgressService _instance = TaskProgressService._internal();
  factory TaskProgressService() => _instance;
  TaskProgressService._internal()
    : _supabaseOverride = null,
      _cache = LocalCacheService();

  TaskProgressService.test({
    SupabaseClient? supabase,
    LocalCacheService? cache,
  }) : _supabaseOverride = supabase,
       _cache = cache ?? LocalCacheService();

  final SupabaseClient? _supabaseOverride;
  final LocalCacheService _cache;

  SupabaseClient get _supabase => _supabaseOverride ?? SupabaseService.client;

  Box? _box;
  static const _boxName = 'task_progress';

  Future<void> initialize() async {
    _box = await openHiveBoxSafelyUntyped(
      _boxName,
      cipher: EncryptionService.cipher,
    );
  }

  String _key(String userId, String taskId) => '$userId:$taskId';

  Map<String, bool>? getProgress(String userId, String taskId) {
    final raw = _box?.get(_key(userId, taskId));
    if (raw == null) return null;
    return {
      'isCompleted': raw['isCompleted'] as bool? ?? false,
      'isSubmitted': raw['isSubmitted'] as bool? ?? false,
    };
  }

  int _updatedAtOf(Map raw) => raw['updatedAt'] as int? ?? 0;

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
        'Error guardando progreso en Supabase, marcando para sync',
        error: e,
        tag: 'TaskProgress',
      );
      await _cache.markPendingSync(
        'progress',
        _key(userId, taskId),
        'update',
      );
    }
  }

  /// Sube a Supabase el progreso guardado localmente para [taskId].
  Future<void> pushProgress(String userId, String taskId) async {
    final raw = _box?.get(_key(userId, taskId));
    if (raw == null) return;
    final localRaw = Map<String, dynamic>.from(raw as Map);

    await _supabase.from('task_progress').upsert({
      'user_id': userId,
      'task_id': taskId,
      'is_completed': localRaw['isCompleted'] as bool? ?? false,
      'is_submitted': localRaw['isSubmitted'] as bool? ?? false,
      'updated_at': _updatedAtOf(localRaw),
    }, onConflict: 'user_id,task_id');
  }

  /// Reconcilia el progreso local (Hive) con Supabase para [userId].
  /// Usa last-write-wins según updated_at.
  Future<void> syncProgress(String userId) async {
    if (_box == null) return;

    Map<String, dynamic> remoteEntries = {};
    try {
      final rows = await _supabase
          .from('task_progress')
          .select()
          .eq('user_id', userId);

      for (final row in rows) {
        remoteEntries[row['task_id'] as String] = {
          'isCompleted': row['is_completed'] as bool? ?? false,
          'isSubmitted': row['is_submitted'] as bool? ?? false,
          'updatedAt': row['updated_at'] as int? ?? 0,
        };
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
        .where((k) => k.startsWith(prefix))
        .toList();

    // Migrar entradas sin updatedAt
    for (final key in localKeys) {
      final raw = Map<String, dynamic>.from(_box!.get(key) as Map);
      if (_updatedAtOf(raw) == 0) {
        raw['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
        await _box!.put(key, raw);
      }
    }

    // Local → remoto
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

    // Remoto → local
    for (final entry in remoteEntries.entries) {
      final taskId = entry.key;
      final remoteRaw = Map<String, dynamic>.from(entry.value as Map);
      final key = _key(userId, taskId);
      final localRaw = _box!.get(key) as Map?;

      if (localRaw == null ||
          _updatedAtOf(remoteRaw) >
              _updatedAtOf(Map<String, dynamic>.from(localRaw))) {
        await _box!.put(key, {
          'isCompleted': remoteRaw['isCompleted'] as bool? ?? false,
          'isSubmitted': remoteRaw['isSubmitted'] as bool? ?? false,
          'updatedAt': _updatedAtOf(remoteRaw),
        });
      }
    }
  }

  /// Stream de cambios en el progreso remoto del usuario.
  Stream<void> watchProgress(String userId) {
    return _supabase
        .from('task_progress')
        .stream(primaryKey: ['user_id', 'task_id'])
        .eq('user_id', userId)
        .asyncMap((rows) async {
          for (final row in rows) {
            final remoteRaw = {
              'isCompleted': row['is_completed'] as bool? ?? false,
              'isSubmitted': row['is_submitted'] as bool? ?? false,
              'updatedAt': row['updated_at'] as int? ?? 0,
            };
            final key = _key(userId, row['task_id'] as String);
            final localRaw = _box?.get(key) as Map?;

            if (localRaw == null ||
                _updatedAtOf(remoteRaw) >
                    _updatedAtOf(Map<String, dynamic>.from(localRaw))) {
              await _box?.put(key, remoteRaw);
            }
          }
        });
  }

  Future<void> clearProgress(String userId, String taskId) async {
    await _box?.delete(_key(userId, taskId));
  }

  Future<void> clearAll() async {
    await _box?.clear();
  }
}
