import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/subject_model.dart';
import '../services/supabase_db_service.dart';
import '../services/local_cache_service.dart';
import '../services/sync_service.dart';
import '../services/career_service.dart';
import '../notification_service.dart';

/// Estado global de la aplicación
/// Centraliza datos y operaciones para evitar inconsistencias entre pantallas
class AppState extends ChangeNotifier {
  final SupabaseDbService _supabase = SupabaseDbService();
  final LocalCacheService _cache = LocalCacheService();
  final SyncService _sync = SyncService();
  
  // Estado de datos
  List<Task> _tasks = [];
  List<Subject> _subjects = [];
  // Contador, no booleano: loadTasks/loadSubjects/forceSync se superponen
  // (forceSync espera a los otros dos con Future.wait), y con un booleano el
  // primero en terminar apagaba isLoading aunque el otro siguiera cargando.
  int _loadingCount = 0;
  String _error = '';
  
  StreamSubscription? _changesSubscription;
  StreamSubscription? _authSubscription;
  
  AppState() {
    _initAuthListener();
    _initCareerListener();
  }
  
  void _initAuthListener() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((authState) {
      final user = authState.session?.user;
      if (user != null) {
        _subscribeToChanges();
        loadTasks();
        loadSubjects();
      } else {
        _unsubscribeFromChanges();
        _tasks = [];
        _subjects = [];
        // La foto es de la cuenta anterior: si sobrevive, la primera carga de
        // la cuenta nueva la compara contra ella y avisa de tareas que llevan
        // ahí desde siempre.
        _sharedTaskSnapshot = null;
        notifyListeners();
      }
    });
  }
  
  /// Se guarda la referencia para poder quitarlo en [dispose]: CareerService
  /// es un singleton, así que un listener anónimo sobrevivía a este AppState y
  /// seguía llamando a loadTasks() sobre un ChangeNotifier ya desechado.
  late final VoidCallback _careerListener;

  void _initCareerListener() {
    _careerListener = () => loadTasks();
    CareerService().addListener(_careerListener);
  }
  
  void _subscribeToChanges() {
    _unsubscribeFromChanges();
    _changesSubscription = _supabase.watchRelevantChanges().listen((_) {
      loadTasks();
    });
  }
  
  void _unsubscribeFromChanges() {
    _changesSubscription?.cancel();
    _changesSubscription = null;
  }
  
  // Getters
  List<Task> get tasks => _tasks;
  List<Subject> get subjects => _subjects;
  bool get isLoading => _loadingCount > 0;
  String get error => _error;
  
  // Getters filtrados
  List<Task> get pendingTasks => _tasks.where((task) {
    final isDelivered = task.isCompleted && task.isSubmitted;
    final isFuture = task.dueDate.isAfter(DateTime.now());
    final matchesCareer = CareerService().matchesAnyCareer(task.careerId);
    return !isDelivered && isFuture && matchesCareer;
  }).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  
  List<Task> get overdueTasks => _tasks.where((task) {
    final isDelivered = task.isCompleted && task.isSubmitted;
    final isPast = task.dueDate.isBefore(DateTime.now());
    final matchesCareer = CareerService().matchesAnyCareer(task.careerId);
    return !isDelivered && isPast && matchesCareer;
  }).toList()
    ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  
  List<Task> get deliveredTasks => _tasks.where((task) {
    final isDelivered = task.isCompleted && task.isSubmitted;
    final matchesCareer = CareerService().matchesAnyCareer(task.careerId);
    return isDelivered && matchesCareer;
  }).toList()
    ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  
  // ==================== TASKS ====================
  
  /// Carga todas las tareas (offline-first)
  Future<void> loadTasks() async {
    _setLoading(true);
    _clearError();
    
    try {
      // 1. Intentar forzar sincronización de cambios pendientes
      await _sync.forceSync();

      // 2. Cargar desde cache primero
      final cachedTasks = _cache.getCachedTasks();
      if (cachedTasks.isNotEmpty) {
        _tasks = cachedTasks;
        notifyListeners();
      }
      
      // 3. Actualizar desde Supabase.
      //
      // getTasks() ya devuelve el progreso personal aplicado
      // (applyCurrentUserProgress), así que acá no se vuelve a aplicar: eran
      // dos pasadas sobre la misma caja de Hive esperando a divergir.
      _tasks = await _supabase.getTasks();
      _clearError();
      _notifySharedTaskChanges(_tasks);
      NotificationService().syncAllTaskReminders(_tasks);
    } catch (e) {
      _setError('Error cargando tareas: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Última foto de las tareas compartidas: id -> huella de su contenido.
  ///
  /// Null hasta la primera carga: sin ese estado inicial, al abrir la app
  /// todas las tareas del grupo se verían como "nuevas" y saldría una
  /// notificación por cada una.
  Map<String, String>? _sharedTaskSnapshot;

  /// Compara la lista recién traída con la anterior y avisa de lo que otra
  /// persona creó o editó en el grupo.
  ///
  /// Solo suena mientras la app esté corriendo: esto se dispara desde la
  /// recarga que provoca la suscripción Realtime, no desde un push. Con la
  /// app cerrada por el sistema no hay nada escuchando.
  void _notifySharedTaskChanges(List<Task> tasks) {
    final user = Supabase.instance.client.auth.currentUser;
    final miId = user?.id;
    final miNombre = user?.userMetadata?['full_name'] as String? ??
        user?.userMetadata?['name'] as String?;

    final compartidas = tasks.where((t) => t.isShared && t.id != null).toList();
    final actual = {
      for (final t in compartidas) t.id!: _huella(t),
    };

    final previo = _sharedTaskSnapshot;
    _sharedTaskSnapshot = actual;
    if (previo == null) return;

    for (final t in compartidas) {
      final antes = previo[t.id!];

      if (antes == null) {
        if (t.userId == miId) continue;
        NotificationService().notifySharedTaskChange(
          title: t.title,
          subject: t.subject,
          author: t.userName,
          isNew: true,
        );
      } else if (antes != actual[t.id!]) {
        // El autor de la última edición lo estampa un trigger del servidor,
        // así que se puede confiar en él para no avisarle a alguien de su
        // propio cambio — cosa que t.userId no permite: en una tarea
        // compartida cualquier miembro edita, pero userId sigue siendo el de
        // quien la creó.
        if (t.updatedByName != null && t.updatedByName == miNombre) continue;
        NotificationService().notifySharedTaskChange(
          title: t.title,
          subject: t.subject,
          author: t.updatedByName ?? t.userName,
          isNew: false,
        );
      }
    }
  }

  /// Huella del contenido visible de una tarea. Los campos de progreso
  /// personal (isCompleted/isSubmitted) quedan fuera a propósito: son de cada
  /// usuario, y marcarla como entregada no es una edición del grupo.
  static String _huella(Task t) => [
        t.title,
        t.description,
        t.subject,
        t.professor,
        t.type,
        t.dueDate.millisecondsSinceEpoch,
        t.updatedAt?.millisecondsSinceEpoch ?? 0,
      ].join('|');

  /// Agrega una tarea. Devuelve la tarea creada (con su id ya asignado) o
  /// `null` si falló, para que quien llame no tenga que adivinar el id.
  Future<Task?> addTask(Task task) async {
    _clearError();
    try {
      final id = await _supabase.addTask(task);
      final newTask = task.copyWith(id: id);
      _tasks.add(newTask);
      notifyListeners();
      NotificationService().syncAllTaskReminders(_tasks);
      return newTask;
    } catch (e) {
      _setError('Error agregando tarea: $e');
      return null;
    }
  }
  
  /// Actualiza una tarea. Devuelve false (y deja el motivo en [error]) si falla.
  Future<bool> updateTask(Task task) async {
    _clearError();
    try {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      final previa = index == -1 ? null : _tasks[index];

      // Cambiar el interruptor de compartir no es una edición: la tarea vive
      // en `tasks` o en `shared_tasks` según ese valor, así que hay que
      // moverla. Un UPDATE no lo hace — tocaría cero filas en la tabla nueva
      // y la tarea se quedaría donde estaba, mostrando en pantalla un estado
      // que el servidor no tiene.
      if (previa != null && previa.isShared != task.isShared) {
        return _moveTaskBetweenTables(previa, task, index);
      }

      await _supabase.updateTask(task);
      if (index != -1) {
        _tasks[index] = task;
        notifyListeners();
        NotificationService().syncAllTaskReminders(_tasks);
      }
      return true;
    } catch (e) {
      _setError('Error actualizando tarea: $e');
      return false;
    }
  }

  /// Recrea la tarea en la tabla que le corresponde y borra la original.
  ///
  /// El id cambia, porque lo genera la base al insertar. Por eso se cancelan
  /// los recordatorios del id viejo antes de reprogramar: si no, quedarían
  /// alarmas huérfanas que nadie puede cancelar.
  Future<bool> _moveTaskBetweenTables(Task previa, Task nueva, int index) async {
    final idViejo = previa.id;
    final creada = await _supabase.addTask(nueva.copyWith(id: null));

    try {
      await _supabase.deleteTask(idViejo!, isShared: previa.isShared);
    } catch (e) {
      // La copia nueva ya existe; dejar la vieja duplicaría la tarea, así que
      // el fallo se reporta en vez de tragarse.
      _setError('La tarea se movió pero no se pudo borrar la anterior: $e');
    }

    await NotificationService().cancelTaskReminders(idViejo!);

    _tasks[index] = nueva.copyWith(id: creada);
    notifyListeners();
    NotificationService().syncAllTaskReminders(_tasks);
    return true;
  }

  /// Elimina una tarea. Devuelve false (y deja el motivo en [error]) si falla.
  Future<bool> deleteTask(String taskId) async {
    _clearError();
    try {
      final matches = _tasks.where((t) => t.id == taskId);
      final isShared = matches.isEmpty ? null : matches.first.isShared;
      await _supabase.deleteTask(taskId, isShared: isShared);
      _tasks.removeWhere((t) => t.id == taskId);
      notifyListeners();
      NotificationService().syncAllTaskReminders(_tasks);
      return true;
    } catch (e) {
      _setError('Error eliminando tarea: $e');
      return false;
    }
  }

  /// Actualiza el estado (isCompleted, isSubmitted) de una tarea.
  /// Devuelve false (y deja el motivo en [error]) si falla.
  Future<bool> updateTaskStatus(
    String taskId,
    bool isCompleted,
    bool isSubmitted,
  ) async {
    _clearError();
    try {
      await _supabase.updateTaskStatus(taskId, isCompleted, isSubmitted);
      final index = _tasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _tasks[index] = _tasks[index].copyWith(
          isCompleted: isCompleted,
          isSubmitted: isSubmitted,
        );
        notifyListeners();
        NotificationService().syncAllTaskReminders(_tasks);
      }
      return true;
    } catch (e) {
      _setError('Error actualizando estado de tarea: $e');
      return false;
    }
  }
  
  // ==================== SUBJECTS ====================
  
  /// Carga todas las materias (offline-first)
  Future<void> loadSubjects() async {
    _setLoading(true);
    _clearError();
    try {
      final cachedSubjects = _cache.getCachedSubjects();
      if (cachedSubjects.isNotEmpty) {
        _subjects = cachedSubjects;
        notifyListeners();
      }
      final subjects = await _supabase.getSubjects();
      _subjects = subjects;
      _clearError();
    } catch (e) {
      _setError('Error cargando materias: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  /// Agrega una materia. Devuelve null (y deja el motivo en [error]) si falla.
  Future<Subject?> addSubject(Subject subject) async {
    _clearError();
    try {
      final id = await _supabase.addSubject(subject);
      final newSubject = subject.copyWith(id: id);
      _subjects.add(newSubject);
      notifyListeners();
      return newSubject;
    } catch (e) {
      _setError('Error agregando materia: $e');
      return null;
    }
  }

  /// Actualiza una materia. Devuelve false (y deja el motivo en [error]) si falla.
  Future<bool> updateSubject(Subject subject) async {
    _clearError();
    try {
      await _supabase.updateSubject(subject);
      final index = _subjects.indexWhere((s) => s.id == subject.id);
      if (index != -1) {
        _subjects[index] = subject;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _setError('Error actualizando materia: $e');
      return false;
    }
  }

  /// Elimina una materia. Devuelve false (y deja el motivo en [error]) si falla.
  Future<bool> deleteSubject(String subjectId) async {
    _clearError();
    try {
      await _supabase.deleteSubject(subjectId);
      _subjects.removeWhere((s) => s.id == subjectId);
      notifyListeners();
      return true;
    } catch (e) {
      _setError('Error eliminando materia: $e');
      return false;
    }
  }
  
  // ==================== SYNC ====================
  
  /// Fuerza sincronización manual
  Future<void> forceSync() async {
    _clearError();
    _setLoading(true);
    
    try {
      await _sync.forceSync();

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
    _loadingCount = loading
        ? _loadingCount + 1
        : (_loadingCount > 0 ? _loadingCount - 1 : 0);
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
  
  @override
  void dispose() {
    _authSubscription?.cancel();
    _changesSubscription?.cancel();
    CareerService().removeListener(_careerListener);
    super.dispose();
  }
}
