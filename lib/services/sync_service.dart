import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'local_cache_service.dart';
import '../firebase_service.dart';
import '../subject_model.dart';
import '../utils/logger.dart';

/// Servicio de sincronización automática entre caché local y Firebase.
///
/// Este servicio escucha cambios de conectividad y sincroniza automáticamente
/// los datos pendientes cuando se restaura la conexión a internet.
///
/// Flujo de trabajo:
/// 1. Cuando no hay conexión, los cambios se guardan en caché local
/// 2. Los cambios pendientes se marcan para sincronización
/// 3. Al recuperar conexión, se sincronizan automáticamente
/// 4. La UI puede mostrar indicadores de estado de sincronización
///
/// Características:
/// - Detección automática de conectividad
/// - Sincronización en background
/// - Stream de estado para UI
/// - Reintentos automáticos
/// - Singleton pattern
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal()
    : _cache = LocalCacheService(),
      _firebase = FirebaseService();

  final LocalCacheService _cache;
  final FirebaseService _firebase;

  /// Constructor para testing (inyección de dependencias)
  /// Permite inyectar mocks para pruebas unitarias
  SyncService.test({
    required LocalCacheService cache,
    required FirebaseService firebase,
  }) : _cache = cache,
       _firebase = firebase;

  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;

  /// Stream para notificar estado de sincronización a la UI
  /// Emite eventos: idle, syncing, completed, partialError, error
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Inicializa el servicio de sync
  void initialize() {
    Logger.sync('SyncService inicializado');

    // FIX: connectivity_plus v5+ emite List<ConnectivityResult>, no ConnectivityResult
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      ConnectivityResult result,
    ) {
      _onConnectivityChanged(result);
    });

    // Verificar sync pendiente al iniciar (por si la app se cerró con cambios sin sync)
    _checkPendingSyncOnStartup();
  }

  /// Verifica si hay sync pendiente al iniciar la app
  Future<void> _checkPendingSyncOnStartup() async {
    final hasConnection = await _cache.hasConnection();
    if (hasConnection) {
      final pending = _cache.getPendingSync();
      if (pending.isNotEmpty) {
        Logger.sync(
          'Hay ${pending.length} cambios pendientes de sincronización',
        );
        await _syncPendingChanges();
      }
    }
  }

  /// Handler para cambios de conectividad
  void _onConnectivityChanged(ConnectivityResult result) async {
    final hasInternet = result != ConnectivityResult.none;

    if (hasInternet && !_isSyncing) {
      // Hay conexión - verificar si hay cambios pendientes
      final pending = _cache.getPendingSync();
      if (pending.isNotEmpty) {
        Logger.sync(
          'Conexión restaurada. Sincronizando ${pending.length} cambios...',
        );
        await _syncPendingChanges();
      }
    }
  }

  /// Sincroniza todos los cambios pendientes
  Future<SyncResult> _syncPendingChanges() async {
    if (_isSyncing) {
      return SyncResult.alreadySyncing;
    }

    _isSyncing = true;
    _statusController.add(SyncStatus.syncing);

    try {
      final pending = _cache.getPendingSync();
      if (pending.isEmpty) {
        _isSyncing = false;
        _statusController.add(SyncStatus.completed);
        return SyncResult.nothingToSync;
      }

      int successCount = 0;
      int errorCount = 0;

      for (final item in pending) {
        try {
          final type = item['type'] as String;
          final id = item['id'] as String;
          final operation = item['operation'] as String;
          final careerId = item['careerId'] as String?;

          await _syncItem(type, id, operation, careerId: careerId);
          successCount++;
        } catch (e) {
          Logger.error(
            'Error sincronizando item',
            error: e,
            tag: 'SyncService',
          );
          errorCount++;
          // No eliminar del pending para reintentar después
        }
      }

      // Si todo fue exitoso, limpiar pending
      if (errorCount == 0) {
        await _cache.clearPendingSync();
        _statusController.add(SyncStatus.completed);
        Logger.sync('Sincronización completada: $successCount items');
      } else {
        _statusController.add(SyncStatus.partialError);
        Logger.warning(
          'Sincronización parcial: $successCount exitosos, $errorCount errores',
          tag: 'SyncService',
        );
      }

      _isSyncing = false;
      return errorCount == 0 ? SyncResult.success : SyncResult.partialError;
    } catch (e) {
      Logger.error(
        'Error general en sincronización',
        error: e,
        tag: 'SyncService',
      );
      _isSyncing = false;
      _statusController.add(SyncStatus.error);
      return SyncResult.error;
    }
  }

  /// Sincroniza un item específico
  Future<void> _syncItem(
    String type,
    String id,
    String operation, {
    String? careerId,
  }) async {
    switch (type) {
      case 'task':
        await _syncTask(id, operation, careerId: careerId);
        break;
      case 'subject':
        await _syncSubject(id, operation);
        break;
    }
  }

  /// Sincroniza una tarea
  Future<void> _syncTask(String id, String operation, {String? careerId}) async {
    final cachedTask = _cache.getCachedTask(id);

    if (cachedTask == null && operation != 'delete') {
      Logger.warning(
        'Tarea $id no encontrada en caché, saltando...',
        tag: 'SyncService',
      );
      return;
    }

    switch (operation) {
      case 'create':
        // Crear en Firebase (sin ID temporal)
        final newTask = cachedTask!.copyWith(id: null);
        final newId = await _firebase.addTask(newTask);

        // Actualizar caché con nuevo ID real
        await _cache.removeCachedTask(id);
        await _cache.cacheTask(cachedTask.copyWith(id: newId));
        Logger.sync('Tarea creada en Firebase: $newId');
        break;

      case 'update':
        if (cachedTask != null) {
          await _firebase.updateTask(cachedTask);
          Logger.sync('Tarea actualizada: $id');
        }
        break;

      case 'delete':
        try {
          await _firebase.deleteTask(id, careerId: careerId ?? cachedTask?.careerId);
          Logger.sync('Tarea eliminada: $id');
        } catch (e) {
          // Si ya no existe en Firebase, ignorar error
          if (!e.toString().contains('not-found')) {
            rethrow;
          }
        }
        break;
    }
  }

  /// Sincroniza una materia
  Future<void> _syncSubject(String id, String operation) async {
    // FIX: para delete no necesitamos el subject del caché
    if (operation == 'delete') {
      try {
        await _firebase.deleteSubject(id);
        Logger.sync('Materia eliminada: $id');
      } catch (e) {
        if (!e.toString().contains('not-found')) {
          rethrow;
        }
      }
      return;
    }

    final cachedSubjects = _cache.getCachedSubjects();
    final matchingSubjects = cachedSubjects.where((s) => s.id == id).toList();
    if (matchingSubjects.isEmpty) {
      Logger.warning(
        'Materia $id no encontrada en caché, saltando...',
        tag: 'SyncService',
      );
      return;
    }
    final cachedSubject = matchingSubjects.first;

    switch (operation) {
      case 'create':
        final newSubject = cachedSubject.copyWith(id: null);
        final newId = await _firebase.addSubject(newSubject);
        await _cache.removeCachedSubject(id);
        await _cache.cacheSubject(cachedSubject.copyWith(id: newId));
        Logger.sync('Materia creada en Firebase: $newId');
        break;

      case 'update':
        await _firebase.updateSubject(cachedSubject);
        Logger.sync('Materia actualizada: $id');
        break;
    }
  }

  /// Fuerza una sincronización manual (útil para pull-to-refresh o botón)
  Future<SyncResult> forceSync() async {
    final hasConnection = await _cache.hasConnection();
    if (!hasConnection) {
      return SyncResult.noConnection;
    }
    return await _syncPendingChanges();
  }

  /// Verifica si hay cambios pendientes
  bool hasPendingChanges() {
    return _cache.getPendingSync().isNotEmpty;
  }

  /// Obtiene cantidad de cambios pendientes
  int get pendingChangesCount {
    return _cache.getPendingSync().length;
  }

  /// Limpia el stream al cerrar
  void dispose() {
    _connectivitySubscription?.cancel();
    _statusController.close();
  }
}

/// Estados de sincronización
enum SyncStatus { idle, syncing, completed, partialError, error }

/// Resultados de sincronización
enum SyncResult {
  success,
  partialError,
  error,
  nothingToSync,
  noConnection,
  alreadySyncing,
}

/// Widget para mostrar indicador de sincronización en la UI
class SyncIndicator extends StatelessWidget {
  final SyncService syncService;

  const SyncIndicator({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: syncService.statusStream,
      initialData: SyncStatus.idle,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;

        switch (status) {
          case SyncStatus.syncing:
            return const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            );
          case SyncStatus.completed:
            return const Icon(Icons.cloud_done, size: 20, color: Colors.white);
          case SyncStatus.partialError:
          case SyncStatus.error:
            return const Icon(Icons.cloud_off, size: 20, color: Colors.orange);
          default:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// Extension para copyWith en Subject
extension SubjectCopyWith on Subject {
  Subject copyWith({
    String? id,
    String? name,
    String? professor,
    String? description,
    SubjectVisibility? visibility,
    String? userId,
    String? userName,
    DateTime? createdAt,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      professor: professor ?? this.professor,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
