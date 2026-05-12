import 'package:flutter/material.dart';
import '../task_model.dart';
import '../subject_model.dart';
import '../firebase_service.dart';
import '../services/local_cache_service.dart';
import '../services/sync_service.dart';

/// Estado global de la aplicación
/// Centraliza datos y operaciones para evitar inconsistencias entre pantallas
class AppState extends ChangeNotifier {
  final FirebaseService _firebase = FirebaseService();
  final LocalCacheService _cache = LocalCacheService();
  final SyncService _sync = SyncService();
  
  // Estado de datos
  List<Task> _tasks = [];
  List<Subject> _subjects = [];
  bool _isLoading = false;
  String _error = '';
  
  // Getters
  List<Task> get tasks => _tasks;
  List<Subject> get subjects => _subjects;
  bool get isLoading => _isLoading;
  String get error => _error;
  
  // Getters filtrados
  List<Task> get pendingTasks => _tasks.where((task) {
    final isDelivered = task.isCompleted && task.isSubmitted;
    final isFuture = task.dueDate.isAfter(DateTime.now());
    return !isDelivered && isFuture;
  }).toList();
  
  List<Task> get overdueTasks => _tasks.where((task) {
    final isDelivered = task.isCompleted && task.isSubmitted;
    final isPast = task.dueDate.isBefore(DateTime.now());
    return !isDelivered && isPast;
  }).toList();
  
  List<Task> get deliveredTasks => _tasks.where((task) => 
    task.isCompleted && task.isSubmitted
  ).toList();
  
  // ==================== TASKS ====================
  
  /// Carga todas las tareas (offline-first)
  Future<void> loadTasks() async {
    _setLoading(true);
    _clearError();
    
    try {
      // Cargar desde cache primero
      final cachedTasks = _cache.getCachedTasks();
      if (cachedTasks.isNotEmpty) {
        _tasks = cachedTasks;
        notifyListeners();
      }
      
      // Actualizar desde Firebase
      final tasks = await _firebase.getTasks();
      _tasks = tasks;
      _clearError();
    } catch (e) {
      _setError('Error cargando tareas: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Agrega una tarea
  Future<void> addTask(Task task) async {
    _clearError();
    
    try {
      final id = await _firebase.addTask(task);
      final newTask = task.copyWith(id: id);
      _tasks.add(newTask);
      notifyListeners();
    } catch (e) {
      _setError('Error agregando tarea: $e');
    }
  }
  
  /// Actualiza una tarea
  Future<void> updateTask(Task task) async {
    _clearError();
    
    try {
      await _firebase.updateTask(task);
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task;
        notifyListeners();
      }
    } catch (e) {
      _setError('Error actualizando tarea: $e');
    }
  }
  
  /// Elimina una tarea
  Future<void> deleteTask(String taskId) async {
    _clearError();
    
    try {
      await _firebase.deleteTask(taskId);
      _tasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
    } catch (e) {
      _setError('Error eliminando tarea: $e');
    }
  }
  
  // ==================== SUBJECTS ====================
  
  /// Carga todas las materias (offline-first)
  Future<void> loadSubjects() async {
    _setLoading(true);
    _clearError();
    
    try {
      // Cargar desde cache primero
      final cachedSubjects = _cache.getCachedSubjects();
      if (cachedSubjects.isNotEmpty) {
        _subjects = cachedSubjects;
        notifyListeners();
      }
      
      // Actualizar desde Firebase
      final subjects = await _firebase.getSubjects();
      _subjects = subjects;
      _clearError();
    } catch (e) {
      _setError('Error cargando materias: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Agrega una materia
  Future<void> addSubject(Subject subject) async {
    _clearError();
    
    try {
      final id = await _firebase.addSubject(subject);
      final newSubject = subject.copyWith(id: id);
      _subjects.add(newSubject);
      notifyListeners();
    } catch (e) {
      _setError('Error agregando materia: $e');
    }
  }
  
  /// Actualiza una materia
  Future<void> updateSubject(Subject subject) async {
    _clearError();
    
    try {
      await _firebase.updateSubject(subject);
      final index = _subjects.indexWhere((s) => s.id == subject.id);
      if (index != -1) {
        _subjects[index] = subject;
        notifyListeners();
      }
    } catch (e) {
      _setError('Error actualizando materia: $e');
    }
  }
  
  /// Elimina una materia
  Future<void> deleteSubject(String subjectId) async {
    _clearError();
    
    try {
      await _firebase.deleteSubject(subjectId);
      _subjects.removeWhere((s) => s.id == subjectId);
      notifyListeners();
    } catch (e) {
      _setError('Error eliminando materia: $e');
    }
  }
  
  // ==================== SYNC ====================
  
  /// Fuerza sincronización manual
  Future<void> forceSync() async {
    _clearError();
    _setLoading(true);
    
    try {
      final result = await _sync.forceSync();
      
      // Recargar datos después de sync
      await Future.wait([
        loadTasks(),
        loadSubjects(),
      ]);
      
      _clearError();
    } catch (e) {
      _setError('Error sincronizando: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Verifica si hay cambios pendientes
  bool get hasPendingChanges => _sync.hasPendingChanges();
  
  /// Stream de estado de sincronización
  Stream<SyncStatus> get syncStatus => _sync.statusStream;
  
  // ==================== UTILS ====================
  
  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
  
  void _setError(String error) {
    _error = error;
    notifyListeners();
  }
  
  void _clearError() {
    if (_error.isNotEmpty) {
      _error = '';
      notifyListeners();
    }
  }
  
  /// Filtra tareas por materia
  List<Task> getTasksBySubject(String subject) {
    if (subject == 'Todos') return _tasks;
    return _tasks.where((task) => task.subject == subject).toList();
  }
  
  /// Obtiene materias únicas para filtros
  List<String> get uniqueSubjects {
    final subjects = _tasks.map((task) => task.subject).toSet().toList();
    subjects.sort();
    return ['Todos', ...subjects];
  }
  
  /// Busca tareas por texto
  List<Task> searchTasks(String query) {
    if (query.isEmpty) return _tasks;
    
    final lowerQuery = query.toLowerCase();
    return _tasks.where((task) =>
      task.title.toLowerCase().contains(lowerQuery) ||
      task.description.toLowerCase().contains(lowerQuery) ||
      task.subject.toLowerCase().contains(lowerQuery) ||
      (task.tag?.toLowerCase().contains(lowerQuery) ?? false)
    ).toList();
  }
}
