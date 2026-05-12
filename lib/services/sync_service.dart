import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'local_cache_service.dart';
import '../firebase_service.dart';
import '../task_model.dart';
import '../subject_model.dart';

/// Servicio de sincronización automática entre caché local y Firebase
/// Escucha cambios de conectividad y sincroniza datos pendientes
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal()
      : _cache = LocalCacheService(),
        _firebase = FirebaseService();

  final LocalCacheService _cache;
  final FirebaseService _firebase;
  
  /// Constructor para testing (inyección de dependencias)
  SyncService.test({
    required LocalCacheService cache,
    required FirebaseService firebase,
  }) : _cache = cache,
       _firebase = firebase;
  
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _isSyncing = false;
  
  /// Stream para notificar estado de sincronización
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;
  
  /// Inicializa el servicio de sync
  void initialize() {
    print('🔄 SyncService inicializado');
    
    // Escuchar cambios en conectividad
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
    
    // Verificar sync pendiente al iniciar (por si la app se cerró con cambios sin sync)
    _checkPendingSyncOnStartup();
  }
  
  /// Verifica si hay sync pendiente al iniciar la app
  Future<void> _checkPendingSyncOnStartup() async {
    final hasConnection = await _cache.hasConnection();
    if (hasConnection) {
      final pending = _cache.getPendingSync();
      if (pending.isNotEmpty) {
        print('📦 Hay ${pending.length} cambios pendientes de sincronización');
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
        print('🌐 Conexión restaurada. Sincronizando ${pending.length} cambios...');
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
          
          await _syncItem(type, id, operation);
          successCount++;
          
        } catch (e) {
          print('❌ Error sincronizando item: $e');
          errorCount++;
          // No eliminar del pending para reintentar después
        }
      }
      
      // Si todo fue exitoso, limpiar pending
      if (errorCount == 0) {
        await _cache.clearPendingSync();
        _statusController.add(SyncStatus.completed);
        print('✅ Sincronización completada: $successCount items');
      } else {
        _statusController.add(SyncStatus.partialError);
        print('⚠️ Sincronización parcial: $successCount exitosos, $errorCount errores');
      }
      
      _isSyncing = false;
      return errorCount == 0 ? SyncResult.success : SyncResult.partialError;
      
    } catch (e) {
      print('❌ Error general en sincronización: $e');
      _isSyncing = false;
      _statusController.add(SyncStatus.error);
      return SyncResult.error;
    }
  }
  
  /// Sincroniza un item específico
  Future<void> _syncItem(String type, String id, String operation) async {
    switch (type) {
      case 'task':
        await _syncTask(id, operation);
        break;
      case 'subject':
        await _syncSubject(id, operation);
        break;
    }
  }
  
  /// Sincroniza una tarea
  Future<void> _syncTask(String id, String operation) async {
    final cachedTask = _cache.getCachedTask(id);
    
    if (cachedTask == null && operation != 'delete') {
      print('⚠️ Tarea $id no encontrada en caché, saltando...');
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
        print('✅ Tarea creada en Firebase: $newId');
        break;
        
      case 'update':
        if (cachedTask != null) {
          await _firebase.updateTask(cachedTask);
          print('✅ Tarea actualizada: $id');
        }
        break;
        
      case 'delete':
        try {
          await _firebase.deleteTask(id);
          print('✅ Tarea eliminada: $id');
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
    final cachedSubjects = _cache.getCachedSubjects();
    final cachedSubject = cachedSubjects.firstWhere(
      (s) => s.id == id,
      orElse: () => throw Exception('Subject not found in cache'),
    );
    
    switch (operation) {
      case 'create':
        final newSubject = cachedSubject.copyWith(id: null);
        final newId = await _firebase.addSubject(newSubject);
        await _cache.removeCachedSubject(id);
        await _cache.cacheSubject(cachedSubject.copyWith(id: newId));
        print('✅ Materia creada en Firebase: $newId');
        break;
        
      case 'update':
        await _firebase.updateSubject(cachedSubject);
        print('✅ Materia actualizada: $id');
        break;
        
      case 'delete':
        try {
          await _firebase.deleteSubject(id);
          print('✅ Materia eliminada: $id');
        } catch (e) {
          if (!e.toString().contains('not-found')) {
            rethrow;
          }
        }
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
enum SyncStatus {
  idle,
  syncing,
  completed,
  partialError,
  error,
}

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
  
  const SyncIndicator({Key? key, required this.syncService}) : super(key: key);
  
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
