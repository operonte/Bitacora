import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'local_cache_service.dart';
import 'task_progress_service.dart';
import 'supabase_db_service.dart';
import '../utils/logger.dart';

/// Servicio de sincronización automática entre caché local y Supabase.
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
      _supabase = SupabaseDbService();

  final LocalCacheService _cache;
  final SupabaseDbService _supabase;

  /// Constructor para testing (inyección de dependencias)
  SyncService.test({
    required LocalCacheService cache,
    required SupabaseDbService supabase,
  }) : _cache = cache,
       _supabase = supabase;

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

    // connectivity_plus v5 emite un ConnectivityResult suelto. Al subir a v6
    // pasa a ser List<ConnectivityResult> y hay que cambiar la firma acá.
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
    final hasInternet = await _cache.hasConnection();

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
      final stillPending = <Map<String, dynamic>>[];

      for (final item in pending) {
        try {
          final type = item['type'] as String;
          final id = item['id'] as String;
          final operation = item['operation'] as String;
          final isShared = item['isShared'] as bool?;

          await _syncItem(type, id, operation, isShared: isShared);
          successCount++;
        } catch (e) {
          Logger.error(
            'Error sincronizando item',
            error: e,
            tag: 'SyncService',
          );
          // Se conserva este item puntual para reintentar después (y solo este,
          // no toda la cola: otros items pueden haberse sincronizado bien en
          // esta misma ronda).
          stillPending.add(item);
        }
      }

      // Reemplaza la cola completa por los items que realmente siguen
      // pendientes. Esto también cubre el caso en que sincronizar un item
      // encoló uno nuevo (p.ej. un reintento de creación que volvió a fallar
      // sin conexión): ese nuevo pendiente ya está en Hive y no se toca aquí.
      await _cache.replacePendingSync(stillPending);

      if (stillPending.isEmpty) {
        _statusController.add(SyncStatus.completed);
        Logger.sync('Sincronización completada: $successCount items');
      } else {
        _statusController.add(SyncStatus.partialError);
        Logger.warning(
          'Sincronización parcial: $successCount exitosos, ${stillPending.length} pendientes',
          tag: 'SyncService',
        );
      }

      _isSyncing = false;
      return stillPending.isEmpty ? SyncResult.success : SyncResult.partialError;
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
    bool? isShared,
  }) async {
    switch (type) {
      case 'task':
        await _syncTask(id, operation, isShared: isShared);
        break;
      case 'subject':
        await _syncSubject(id, operation);
        break;
      case 'progress':
        await _syncProgress(id, operation);
        break;
    }
  }

  /// Sincroniza progreso personal pendiente (id con formato '$userId:$taskId')
  Future<void> _syncProgress(String id, String operation) async {
    final parts = id.split(':');
    if (parts.length != 2) {
      Logger.warning('ID de progreso inválido: $id', tag: 'SyncService');
      return;
    }
    final userId = parts[0];
    final taskId = parts[1];

    final progressService = TaskProgressService();
    if (progressService.getProgress(userId, taskId) == null) {
      Logger.warning(
        'Progreso $id no encontrado en caché, saltando...',
        tag: 'SyncService',
      );
      return;
    }

    await progressService.pushProgress(userId, taskId);
    Logger.sync('Progreso sincronizado: $id');
  }

  /// Sincroniza una tarea
  Future<void> _syncTask(String id, String operation, {bool? isShared}) async {
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
        final newTask = cachedTask!.copyWith(id: null);
        // Usar la variante que lanza en caso de fallo: si el reintento
        // falla, debe quedar registrado como error para volver a
        // intentarlo, no perderse silenciosamente.
        final newId = await _supabase.createTaskRemote(newTask);
        await _cache.removeCachedTask(id);
        await _cache.cacheTask(cachedTask.copyWith(id: newId));
        Logger.sync('Tarea creada en Supabase: $newId');
        break;

      case 'update':
        if (cachedTask != null) {
          try {
            await _supabase.updateTaskRemote(cachedTask);
            Logger.sync('Tarea actualizada: $id');
          } on TaskWriteRejectedException catch (e) {
            // Rechazada por el servidor (borrada, o sin permiso). Reintentarla
            // eternamente solo dejaría la cola atascada: se descarta.
            Logger.warning(
              'Se descarta la actualización pendiente de $id: $e',
              tag: 'SyncService',
            );
          }
        }
        break;

      case 'delete':
        try {
          await _supabase.deleteTaskRemote(
              id, isShared: isShared ?? cachedTask?.isShared);
          Logger.sync('Tarea eliminada: $id');
        } catch (e) {
          if (!e.toString().contains('not-found') &&
              !e.toString().contains('PGRST116')) {
            rethrow;
          }
        }
        break;
    }
  }

  /// Sincroniza una materia
  Future<void> _syncSubject(String id, String operation) async {
    if (operation == 'delete') {
      try {
        await _supabase.deleteSubjectRemote(id);
        Logger.sync('Materia eliminada: $id');
      } catch (e) {
        if (!e.toString().contains('not-found') &&
            !e.toString().contains('PGRST116')) {
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
        final newId = await _supabase.createSubjectRemote(newSubject);
        await _cache.removeCachedSubject(id);
        await _cache.cacheSubject(cachedSubject.copyWith(id: newId));
        Logger.sync('Materia creada en Supabase: $newId');
        break;

      case 'update':
        await _supabase.updateSubjectRemote(cachedSubject);
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
    final themeColor = Theme.of(context).colorScheme.onSurface;

    return StreamBuilder<SyncStatus>(
      stream: syncService.statusStream,
      initialData: SyncStatus.idle,
      builder: (context, snapshot) {
        final status = snapshot.data ?? SyncStatus.idle;

        switch (status) {
          case SyncStatus.syncing:
            return SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(themeColor),
              ),
            );
          case SyncStatus.completed:
            return const Icon(Icons.cloud_done, size: 20);
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
