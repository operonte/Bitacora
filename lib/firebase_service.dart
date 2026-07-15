import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/app_firestore.dart';
import 'task_model.dart';
import 'subject_model.dart';
import 'models/career_model.dart';
import 'services/career_service.dart';
import 'services/local_cache_service.dart';
import 'services/task_progress_service.dart';
import 'utils/logger.dart';

/// Servicio de Firebase para gestión de tareas y materias.
///
/// Proporciona una capa de abstracción sobre Firebase Firestore y Auth
/// con soporte para caché local y manejo de errores offline.
///
/// Características:
/// - CRUD de tareas y materias
/// - Caché local automático con Hive
/// - Fallback a caché cuando no hay conexión
/// - Filtrado por carrera
/// - Singleton pattern
class FirebaseService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final LocalCacheService _cache;

  /// Constructor principal (privado para singleton)
  /// Inicializa Firestore con databaseId 'bitacora' y usa instancias singleton de Auth y Cache
  FirebaseService._internal()
    : _firestore = AppFirestore.instance,
      _auth = FirebaseAuth.instance,
      _cache = LocalCacheService();

  /// Constructor para testing (inyección de dependencias)
  /// Permite inyectar mocks de Firestore y Auth para pruebas unitarias
  FirebaseService.test({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    LocalCacheService? cache,
  }) : _firestore = firestore,
       _auth = auth,
       _cache = cache ?? LocalCacheService();

  /// Singleton instance - asegura una única instancia en toda la app
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;

  /// Usuario autenticado actual (null si no hay sesión)
  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      Logger.auth('Iniciando sesión con Google');
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      final result = await _auth.signInWithProvider(googleProvider);
      Logger.auth('Sesión iniciada exitosamente con Google');
      return result;
    } catch (e) {
      Logger.error(
        'Error en signInWithGoogle',
        error: e,
        tag: 'FirebaseService',
      );
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  CollectionReference get tasksCollection {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    return _firestore
        .collection('bitacora')
        .doc(user.uid)
        .collection('tasks');
  }

  CollectionReference get subjectsCollection {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Usuario no autenticado');
    return _firestore
        .collection('bitacora')
        .doc(user.uid)
        .collection('subjects');
  }

  /// Colección de tareas "pendientes" compartidas entre todos los usuarios
  /// que tienen seleccionada la carrera [careerId].
  CollectionReference sharedTasksCollection(String careerId) {
    if (_auth.currentUser == null) throw Exception('Usuario no autenticado');
    return _firestore
        .collection('sharedTasks')
        .doc(careerId)
        .collection('tasks');
  }

  /// Registra (o actualiza) las carreras del usuario actual en
  /// `userCareers/{uid}`, usadas por las reglas de Firestore para autorizar el
  /// acceso a `sharedTasks/{careerId}`.
  ///
  /// Escribe `careerIds` (array con todas las carreras del usuario) y también
  /// `careerId` (la activa) por compatibilidad con reglas/datos antiguos.
  Future<void> registerCareerMemberships() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final careerService = CareerService();
    final ids = careerService.careerIds;
    if (ids.isEmpty) return;

    try {
      await _firestore.collection('userCareers').doc(user.uid).set({
        'careerIds': ids,
        'careerId': careerService.getSelectedCareer()?.id ?? ids.first,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      Logger.warning(
        'Error registrando carreras del usuario',
        error: e,
        tag: 'FirebaseService',
      );
    }
  }

  /// Devuelve la colección donde debe guardarse una tarea según su carrera:
  /// compartida (`sharedTasks/{careerId}/tasks`) o personal (`tasksCollection`).
  CollectionReference _collectionForTask(String? careerId) {
    if (Careers.isShared(careerId)) {
      return sharedTasksCollection(careerId!);
    }
    return tasksCollection;
  }

  Future<String> addTask(Task task) async {
    final taskData = task.toMap();

    try {
      Logger.database('Agregando tarea: ${task.title}');
      final docRef = await _collectionForTask(task.careerId).add(taskData);
      final newTask = task.copyWith(id: docRef.id);

      // Guardar en caché local
      await _cache.cacheTask(newTask);
      Logger.database('Tarea agregada exitosamente con ID: ${docRef.id}');

      return docRef.id;
    } catch (e) {
      // Si falla Firebase (sin internet), guardar en caché para sync posterior
      Logger.warning(
        'Error guardando en Firebase, guardando en caché',
        error: e,
        tag: 'FirebaseService',
      );
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final newTask = task.copyWith(id: tempId);
      await _cache.cacheTask(newTask);
      await _cache.markPendingSync('task', tempId, 'create');
      return tempId;
    }
  }

  Future<void> updateTask(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for update');

    try {
      Logger.database('Actualizando tarea: ${task.id}');
      await _collectionForTask(task.careerId).doc(task.id).update(task.toMap());
      // Actualizar caché
      await _cache.cacheTask(task);
      Logger.database('Tarea actualizada exitosamente');
    } catch (e) {
      Logger.warning(
        'Error actualizando en Firebase, guardando en caché',
        error: e,
        tag: 'FirebaseService',
      );
      await _cache.cacheTask(task);
      await _cache.markPendingSync('task', task.id!, 'update', careerId: task.careerId);
    }
  }

  Future<void> deleteTask(String taskId, {String? careerId}) async {
    try {
      Logger.database('Eliminando tarea: $taskId');
      await _collectionForTask(careerId).doc(taskId).delete();
      // Eliminar del caché
      await _cache.removeCachedTask(taskId);
      Logger.database('Tarea eliminada exitosamente');
    } catch (e) {
      Logger.warning(
        'Error eliminando en Firebase, marcando para sync',
        error: e,
        tag: 'FirebaseService',
      );
      await _cache.removeCachedTask(taskId);
      await _cache.markPendingSync('task', taskId, 'delete', careerId: careerId);
    }
  }

  Future<List<Task>> getTasks({String? careerId}) async {
    try {
      Logger.database(
        'Cargando tareas${careerId != null ? ' para carrera: $careerId' : ''}',
      );
      
      late QuerySnapshot snapshot;
      
      try {
        // Intentar con orderBy createdAt primero
        Query query = tasksCollection.orderBy('createdAt', descending: true);
        if (careerId != null && careerId.isNotEmpty) {
          query = query.where('careerId', isEqualTo: careerId);
        }
        snapshot = await query.get();
      } catch (e) {
        Logger.warning(
          'No se pudo ordenar por createdAt, intentando sin ordenamiento: $e',
          tag: 'FirebaseService',
        );
        // Fallback: obtener sin ordenamiento
        Query query = tasksCollection;
        if (careerId != null && careerId.isNotEmpty) {
          query = query.where('careerId', isEqualTo: careerId);
        }
        snapshot = await query.get();
      }

      final tasks = <Task>[];
      for (final doc in snapshot.docs) {
        try {
          final rawData = doc.data() as Map;
          late Map<String, dynamic> data;
          if (rawData is Map<String, dynamic>) {
            data = rawData;
          } else {
            data = rawData.cast<String, dynamic>();
          }
          final task = Task.fromMap(data, doc.id);
          tasks.add(task);
        } catch (e) {
          Logger.error(
            'Error parseando tarea ${doc.id}: $e. Datos: ${doc.data()}',
            error: e,
            tag: 'FirebaseService',
          );
          // Continuar con la siguiente tarea en lugar de fallar completamente
        }
      }

      // Agregar tareas compartidas de TODAS las carreras del usuario.
      // Si se pasó un [careerId] explícito, solo esa; si no, todas las
      // carreras compartidas a las que pertenece.
      final sharedCareerIds = careerId != null
          ? (Careers.isShared(careerId) ? [careerId] : <String>[])
          : CareerService().careerIds.where(Careers.isShared).toList();
      if (sharedCareerIds.isNotEmpty) {
        // Registrar membresías para que las reglas de Firestore autoricen.
        await registerCareerMemberships();
        final existingIds = tasks.map((t) => t.id).toSet();
        for (final sharedCareerId in sharedCareerIds) {
          try {
            final sharedSnapshot =
                await sharedTasksCollection(sharedCareerId).get();
            for (final doc in sharedSnapshot.docs) {
              if (existingIds.contains(doc.id)) continue;
              try {
                final rawData = doc.data() as Map;
                final data = rawData is Map<String, dynamic>
                    ? rawData
                    : rawData.cast<String, dynamic>();
                tasks.add(Task.fromMap(data, doc.id));
                existingIds.add(doc.id);
              } catch (e) {
                Logger.error(
                  'Error parseando tarea compartida ${doc.id}: $e',
                  error: e,
                  tag: 'FirebaseService',
                );
              }
            }
          } catch (e) {
            Logger.warning(
              'Error cargando tareas compartidas de $sharedCareerId',
              error: e,
              tag: 'FirebaseService',
            );
          }
        }
      }

      // Guardar en caché para uso offline
      await _cache.cacheTasks(tasks);
      Logger.database('Tareas cargadas exitosamente: ${tasks.length} tareas');

      // Sincronizar progreso personal (Realizada/Enviada) entre dispositivos
      final uid = _auth.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) {
        try {
          await TaskProgressService().syncProgress(uid);
        } catch (e) {
          Logger.warning(
            'Error sincronizando progreso personal',
            error: e,
            tag: 'FirebaseService',
          );
        }
      }

      return applyCurrentUserProgress(tasks);
    } catch (e) {
      Logger.warning(
        'Error cargando desde Firebase, usando caché local',
        error: e,
        tag: 'FirebaseService',
      );
      // Si falla Firebase, retornar desde caché
      return _cache.getCachedTasks();
    }
  }

  List<Task> applyCurrentUserProgress(List<Task> tasks) {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return tasks;

    final progressService = TaskProgressService();
    return tasks.map((task) {
      final taskId = task.id;
      if (taskId == null || taskId.isEmpty) return task;

      final progress = progressService.getProgress(uid, taskId);
      if (progress == null) return task;

      return task.copyWith(
        isCompleted: progress['isCompleted'] ?? task.isCompleted,
        isSubmitted: progress['isSubmitted'] ?? task.isSubmitted,
      );
    }).toList();
  }

  /// Emite un evento cada vez que cambian tareas o progreso del usuario.
  /// Útil para refrescar pantallas en tiempo real entre web y APK.
  Stream<void> watchRelevantChanges({String? careerId}) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<void>.error(Exception('Usuario no autenticado'));
    }

    final controller = StreamController<void>.broadcast();
    StreamSubscription? personalTasksSubscription;
    final sharedTasksSubscriptions = <StreamSubscription>[];
    StreamSubscription? progressSubscription;

    void emitChange() {
      if (!controller.isClosed) {
        controller.add(null);
      }
    }

    personalTasksSubscription = tasksCollection.snapshots().listen(
      (_) => emitChange(),
      onError: controller.addError,
    );

    final sharedCareerIds = careerId != null
        ? (Careers.isShared(careerId) ? [careerId] : <String>[])
        : CareerService().careerIds.where(Careers.isShared).toList();
    for (final sharedCareerId in sharedCareerIds) {
      sharedTasksSubscriptions.add(
        sharedTasksCollection(sharedCareerId).snapshots().listen(
          (_) => emitChange(),
          onError: controller.addError,
        ),
      );
    }

    progressSubscription = TaskProgressService().watchProgress(user.uid).listen(
      (_) => emitChange(),
      onError: controller.addError,
    );

    controller.onCancel = () async {
      await personalTasksSubscription?.cancel();
      for (final sub in sharedTasksSubscriptions) {
        await sub.cancel();
      }
      await progressSubscription?.cancel();
    };

    return controller.stream;
  }

  /// Obtiene tareas solo del caché local (útil para mostrar datos inmediatamente)
  List<Task> getTasksFromCache() {
    return _cache.getCachedTasks();
  }

  Future<List<Task>> getPendingTasks() async {
    try {
      late QuerySnapshot snapshot;
      
      try {
        snapshot = await tasksCollection.orderBy('dueDate').get();
      } catch (e) {
        Logger.warning(
          'No se pudo ordenar getPendingTasks por dueDate, intentando sin ordenamiento: $e',
          tag: 'FirebaseService',
        );
        snapshot = await tasksCollection.get();
      }
      
      final tasks = <Task>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          final task = Task.fromMap(data, doc.id);
          tasks.add(task);
        } catch (e) {
          Logger.error(
            'Error parseando tarea ${doc.id} en getPendingTasks: $e. Datos: ${doc.data()}',
            error: e,
            tag: 'FirebaseService',
          );
        }
      }
      // Filtrar: no entregadas (ambos true) Y fecha futura
      return tasks.where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isFuture = task.dueDate.isAfter(DateTime.now());
        return !isDelivered && isFuture;
      }).toList();
    } catch (e) {
      Logger.warning('Error en getPendingTasks: $e', error: e, tag: 'FirebaseService');
      return [];
    }
  }

  Future<List<Task>> getOverdueTasks() async {
    try {
      late QuerySnapshot snapshot;
      
      try {
        snapshot = await tasksCollection
            .orderBy('dueDate', descending: true)
            .get();
      } catch (e) {
        Logger.warning(
          'No se pudo ordenar getOverdueTasks por dueDate, intentando sin ordenamiento: $e',
          tag: 'FirebaseService',
        );
        snapshot = await tasksCollection.get();
      }
      
      final tasks = <Task>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          final task = Task.fromMap(data, doc.id);
          tasks.add(task);
        } catch (e) {
          Logger.error(
            'Error parseando tarea ${doc.id} en getOverdueTasks: $e. Datos: ${doc.data()}',
            error: e,
            tag: 'FirebaseService',
          );
        }
      }
      // Filtrar: no entregadas (ambos true) Y fecha pasada
      return tasks.where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isPast = task.dueDate.isBefore(DateTime.now());
        return !isDelivered && isPast;
      }).toList();
    } catch (e) {
      Logger.warning('Error en getOverdueTasks: $e', error: e, tag: 'FirebaseService');
      return [];
    }
  }

  Future<List<Task>> getDeliveredTasks() async {
    try {
      late QuerySnapshot snapshot;
      
      try {
        snapshot = await tasksCollection
            .orderBy('dueDate', descending: true)
            .get();
      } catch (e) {
        Logger.warning(
          'No se pudo ordenar getDeliveredTasks por dueDate, intentando sin ordenamiento: $e',
          tag: 'FirebaseService',
        );
        snapshot = await tasksCollection.get();
      }
      
      final tasks = <Task>[];
      for (final doc in snapshot.docs) {
        try {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          final task = Task.fromMap(data, doc.id);
          tasks.add(task);
        } catch (e) {
          Logger.error(
            'Error parseando tarea ${doc.id} en getDeliveredTasks: $e. Datos: ${doc.data()}',
            error: e,
            tag: 'FirebaseService',
          );
        }
      }
      // Filtrar: entregadas (ambos true)
      return tasks.where((task) => task.isCompleted && task.isSubmitted).toList();
    } catch (e) {
      Logger.warning('Error en getDeliveredTasks: $e', error: e, tag: 'FirebaseService');
      return [];
    }
  }

  Future<void> updateTaskStatus(
    String taskId,
    bool isCompleted,
    bool isSubmitted,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final cached = _cache.getCachedTask(taskId);
    final isShared = cached != null && Careers.isShared(cached.careerId);

    if (isShared) {
      Logger.database('Actualizando estado de tarea compartida: $taskId en TaskProgressService');
      final progressService = TaskProgressService();
      await progressService.setProgress(
        user.uid,
        taskId,
        isCompleted: isCompleted,
        isSubmitted: isSubmitted,
      );

      // Actualizar localmente el caché con el estado actualizado
      final updated = cached.copyWith(
        isCompleted: isCompleted,
        isSubmitted: isSubmitted,
      );
      await _cache.cacheTask(updated);
    } else {
      try {
        Logger.database(
          'Actualizando estado de tarea personal: $taskId (completada: $isCompleted, enviada: $isSubmitted)',
        );
        await tasksCollection.doc(taskId).update({
          'isCompleted': isCompleted,
          'isSubmitted': isSubmitted,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        if (cached != null) {
          final updated = cached.copyWith(
            isCompleted: isCompleted,
            isSubmitted: isSubmitted,
          );
          await _cache.cacheTask(updated);
        }
      } catch (e) {
        Logger.warning(
          'Sin conexión al actualizar estado personal, guardando en caché',
          error: e,
          tag: 'FirebaseService',
        );
        if (cached != null) {
          final updated = cached.copyWith(
            isCompleted: isCompleted,
            isSubmitted: isSubmitted,
          );
          await _cache.cacheTask(updated);
          await _cache.markPendingSync('task', taskId, 'update');
        }
      }
    }
  }

  Future<void> toggleTaskCompletion(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for toggle');
    final user = _auth.currentUser;
    if (user == null) return;

    final isShared = Careers.isShared(task.careerId);
    final newCompleted = !task.isCompleted;

    if (isShared) {
      Logger.database('Alternando completado de tarea compartida: ${task.id} en TaskProgressService');
      final progressService = TaskProgressService();
      await progressService.setProgress(
        user.uid,
        task.id!,
        isCompleted: newCompleted,
        isSubmitted: task.isSubmitted,
      );
      final updated = task.copyWith(isCompleted: newCompleted);
      await _cache.cacheTask(updated);
    } else {
      try {
        Logger.database('Alternando completado de tarea personal: ${task.id}');
        await tasksCollection.doc(task.id).update({
          'isCompleted': newCompleted,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
        final updated = task.copyWith(isCompleted: newCompleted);
        await _cache.cacheTask(updated);
      } catch (e) {
        Logger.warning(
          'Sin conexión al hacer toggle personal, guardando en caché',
          error: e,
          tag: 'FirebaseService',
        );
        final updated = task.copyWith(isCompleted: newCompleted);
        await _cache.cacheTask(updated);
        await _cache.markPendingSync('task', task.id!, 'update');
      }
    }
  }

  // ==================== SUBJECTS METHODS ====================

  Future<String> addSubject(Subject subject) async {
    final subjectData = subject.toMap();

    try {
      Logger.database('Agregando materia: ${subject.name}');
      final docRef = await subjectsCollection.add(subjectData);
      final newSubject = subject.copyWith(id: docRef.id);

      // Guardar en caché local
      await _cache.cacheSubject(newSubject);
      Logger.database('Materia agregada exitosamente con ID: ${docRef.id}');

      return docRef.id;
    } catch (e) {
      Logger.warning(
        'Error guardando materia en Firebase, guardando en caché',
        error: e,
        tag: 'FirebaseService',
      );
      final tempId = 'temp_subject_${DateTime.now().millisecondsSinceEpoch}';
      final newSubject = subject.copyWith(id: tempId);
      await _cache.cacheSubject(newSubject);
      await _cache.markPendingSync('subject', tempId, 'create');
      return tempId;
    }
  }

  Future<void> updateSubject(Subject subject) async {
    if (subject.id == null) {
      throw Exception('Subject ID is required for update');
    }

    try {
      Logger.database('Actualizando materia: ${subject.id}');
      await subjectsCollection.doc(subject.id).update(subject.toMap());
      await _cache.cacheSubject(subject);
      Logger.database('Materia actualizada exitosamente');
    } catch (e) {
      Logger.warning(
        'Error actualizando materia en Firebase, guardando en caché',
        error: e,
        tag: 'FirebaseService',
      );
      await _cache.cacheSubject(subject);
      await _cache.markPendingSync('subject', subject.id!, 'update');
    }
  }

  Future<void> deleteSubject(String subjectId) async {
    try {
      Logger.database('Eliminando materia: $subjectId');
      await subjectsCollection.doc(subjectId).delete();
      await _cache.removeCachedSubject(subjectId);
      Logger.database('Materia eliminada exitosamente');
    } catch (e) {
      Logger.warning(
        'Error eliminando materia en Firebase, marcando para sync',
        error: e,
        tag: 'FirebaseService',
      );
      await _cache.removeCachedSubject(subjectId);
      await _cache.markPendingSync('subject', subjectId, 'delete');
    }
  }

  Future<List<Subject>> getSubjects() async {
    try {
      Logger.database('Cargando materias');
      final snapshot = await subjectsCollection.orderBy('name').get();

      final subjects = snapshot.docs
          .map(
            (doc) =>
                Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id),
          )
          .toList();

      // Guardar en caché para uso offline
      await _cache.cacheSubjects(subjects);
      Logger.database(
        'Materias cargadas exitosamente: ${subjects.length} materias',
      );

      return subjects;
    } catch (e) {
      Logger.warning(
        'Error cargando materias desde Firebase, usando caché local',
        error: e,
        tag: 'FirebaseService',
      );
      // Si falla Firebase, retornar desde caché
      return _cache.getCachedSubjects();
    }
  }

  /// Obtiene materias solo del caché local
  List<Subject> getSubjectsFromCache() {
    return _cache.getCachedSubjects();
  }

  Future<List<Subject>> getPublicSubjects() async {
    try {
      Logger.database('Cargando materias públicas');
      final snapshot = await subjectsCollection
          .where('visibility', isEqualTo: SubjectVisibility.cursoCompleto.index)
          .orderBy('name')
          .get();
      final subjects = snapshot.docs
          .map(
            (doc) =>
                Subject.fromMap(doc.data() as Map<String, dynamic>, doc.id),
          )
          .toList();
      Logger.database(
        'Materias públicas cargadas: ${subjects.length} materias',
      );
      return subjects;
    } catch (e) {
      Logger.warning(
        'Error cargando materias públicas',
        error: e,
        tag: 'FirebaseService',
      );
      // Retornar vacío si falla - no usar caché para datos públicos
      return [];
    }
  }
}
