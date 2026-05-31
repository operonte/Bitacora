import 'dart:async';
import 'package:hive/hive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../task_model.dart';
import '../subject_model.dart';
import '../utils/logger.dart';

/// Servicio de caché local para soporte offline
/// Usa Hive para almacenamiento local y maneja sincronización con Firebase
class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  Box<Map>? _tasksBox;
  Box<Map>? _subjectsBox;
  Box? _metadataBox;

  bool _initialized = false;

  /// Stream para notificar cambios en conectividad
  StreamSubscription? _connectivitySubscription;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  /// Inicializa Hive y abre las boxes
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Hive ya debe estar inicializado en main.dart con hive_flutter
      _tasksBox = await Hive.openBox<Map>('tasks_cache');
      _subjectsBox = await Hive.openBox<Map>('subjects_cache');
      _metadataBox = await Hive.openBox('metadata_cache');

      // FIX: connectivity_plus v5+ emite List<ConnectivityResult>, no ConnectivityResult
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
        ConnectivityResult result,
      ) {
        _onConnectivityChanged(result);
      });

      _initialized = true;
      Logger.info('LocalCacheService inicializado', tag: 'Cache');
    } catch (e) {
      Logger.error('Error inicializando LocalCacheService: $e', tag: 'Cache');
      rethrow;
    }
  }

  /// Verifica si hay conexión a internet
  Future<bool> hasConnection() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  /// Handler para cambios de conectividad
  void _onConnectivityChanged(ConnectivityResult result) {
    final hasInternet = result != ConnectivityResult.none;
    _connectionController.add(hasInternet);
    Logger.info('Conectividad cambiada: ${hasInternet ? "Online" : "Offline"}', tag: 'Cache');
  }

  // ==================== TASKS CACHE ====================

  /// Guarda una tarea en caché local
  Future<void> cacheTask(Task task) async {
    if (!_initialized) return;

    await _tasksBox?.put(task.id, task.toMap());
    await _metadataBox?.put(
      'last_task_update_${task.id}',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Guarda múltiples tareas en caché
  Future<void> cacheTasks(List<Task> tasks) async {
    if (!_initialized) return;

    for (final task in tasks) {
      if (task.id != null) {
        await _tasksBox?.put(task.id, task.toMap());
      }
    }
    await _metadataBox?.put(
      'last_tasks_sync',
      DateTime.now().millisecondsSinceEpoch,
    );
    Logger.info('${tasks.length} tareas guardadas en caché local', tag: 'Cache');
  }

  /// Obtiene todas las tareas del caché local
  List<Task> getCachedTasks() {
    if (!_initialized) return [];

    return _tasksBox?.values
            .map(
              (data) => Task.fromMap(
                Map<String, dynamic>.from(data),
                data['id'] as String?,
              ),
            )
            .toList() ??
        [];
  }

  /// Obtiene una tarea específica del caché
  Task? getCachedTask(String taskId) {
    if (!_initialized) return null;

    final data = _tasksBox?.get(taskId);
    if (data == null) return null;

    return Task.fromMap(Map<String, dynamic>.from(data), taskId);
  }

  /// Elimina una tarea del caché
  Future<void> removeCachedTask(String taskId) async {
    if (!_initialized) return;
    await _tasksBox?.delete(taskId);
  }

  // ==================== SUBJECTS CACHE ====================

  /// Guarda una materia en caché local
  Future<void> cacheSubject(Subject subject) async {
    if (!_initialized || subject.id == null) return;

    await _subjectsBox?.put(subject.id, subject.toMap());
  }

  /// Guarda múltiples materias en caché
  Future<void> cacheSubjects(List<Subject> subjects) async {
    if (!_initialized) return;

    for (final subject in subjects) {
      if (subject.id != null) {
        await _subjectsBox?.put(subject.id, subject.toMap());
      }
    }
    await _metadataBox?.put(
      'last_subjects_sync',
      DateTime.now().millisecondsSinceEpoch,
    );
    Logger.info('${subjects.length} materias guardadas en caché local', tag: 'Cache');
  }

  /// Obtiene todas las materias del caché local
  List<Subject> getCachedSubjects() {
    if (!_initialized) return [];

    return _subjectsBox?.values
            .map(
              (data) => Subject.fromMap(
                Map<String, dynamic>.from(data),
                data['id'] as String?,
              ),
            )
            .toList() ??
        [];
  }

  /// Elimina una materia del caché
  Future<void> removeCachedSubject(String subjectId) async {
    if (!_initialized) return;
    await _subjectsBox?.delete(subjectId);
  }

  // ==================== SYNC & METADATA ====================

  /// Marca que hay cambios pendientes de sincronización
  Future<void> markPendingSync(
    String entityType,
    String entityId,
    String operation,
  ) async {
    final pending =
        _metadataBox?.get('pending_sync', defaultValue: <Map>[]) as List? ?? [];
    pending.add({
      'type': entityType,
      'id': entityId,
      'operation': operation, // 'create', 'update', 'delete'
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await _metadataBox?.put('pending_sync', pending);
  }

  /// Obtiene cambios pendientes de sincronización
  List<Map<String, dynamic>> getPendingSync() {
    final pending =
        _metadataBox?.get('pending_sync', defaultValue: <Map>[]) as List? ?? [];
    return pending.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  /// Limpia los cambios pendientes
  Future<void> clearPendingSync() async {
    await _metadataBox?.put('pending_sync', <Map>[]);
  }

  /// Obtiene la última fecha de sincronización
  DateTime? getLastSyncTime(String entityType) {
    final timestamp = _metadataBox?.get('last_${entityType}_sync') as int?;
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  /// Limpia todo el caché (útil para logout)
  Future<void> clearAllCache() async {
    if (!_initialized) return;

    await _tasksBox?.clear();
    await _subjectsBox?.clear();
    await _metadataBox?.clear();
    Logger.info('Caché local limpiado completamente', tag: 'Cache');
  }

  /// Cierra las boxes y libera recursos
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _connectionController.close();
    await _tasksBox?.close();
    await _subjectsBox?.close();
    await _metadataBox?.close();
    _initialized = false;
  }
}
