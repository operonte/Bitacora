import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/subject_model.dart';
import '../models/career_model.dart';
import 'career_service.dart';
import 'local_cache_service.dart';
import 'task_progress_service.dart';
import 'supabase_service.dart';
import '../utils/logger.dart';

/// Servicio de base de datos usando Supabase.
///
/// Reemplaza FirebaseService con llamadas a Supabase (PostgreSQL + RLS).
/// Mantiene el mismo patrón offline-first con Hive como caché local.
///
/// Tablas usadas:
/// - tasks          → tareas personales del usuario
/// - shared_tasks   → tareas compartidas por carrera
/// - subjects       → materias personales
/// - user_careers   → membresías usuario-carrera
/// - task_progress  → progreso personal en tareas compartidas
class SupabaseDbService {
  static final SupabaseDbService _instance = SupabaseDbService._internal();
  factory SupabaseDbService() => _instance;
  SupabaseDbService._internal()
    : _client = SupabaseService.client,
      _cache = LocalCacheService();

  /// Constructor para testing
  SupabaseDbService.test({
    required SupabaseClient client,
    LocalCacheService? cache,
  }) : _client = client,
       _cache = cache ?? LocalCacheService();

  final SupabaseClient _client;
  final LocalCacheService _cache;

  // ── Helpers de usuario ──────────────────────────────────────

  User? get currentUser => _client.auth.currentUser;

  String get _uid {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw Exception('Usuario no autenticado');
    return uid;
  }

  // ── Conversión de modelos ────────────────────────────────────

  /// Convierte un Task al formato de columnas de Supabase
  Map<String, dynamic> _taskToRow(Task task, {required bool isShared}) {
    final map = <String, dynamic>{
      'title': task.title,
      'description': task.description,
      'subject': task.subject,
      'professor': task.professor,
      'due_date': task.dueDate.millisecondsSinceEpoch,
      'type': task.type,
      'created_at': task.createdAt.millisecondsSinceEpoch,
      'tag': task.tag,
      'user_id': task.userId,
      'user_name': task.userName,
      if (task.careerId != null && task.careerId!.isNotEmpty)
        'career_id': task.careerId,
      'collaborators': task.collaborators,
    };
    if (isShared) {
      map['created_by'] = _uid;
    } else {
      map['is_completed'] = task.isCompleted;
      map['is_submitted'] = task.isSubmitted;
    }
    return map;
  }

  /// Convierte una fila de Supabase en un Task
  Task _rowToTask(Map<String, dynamic> row) {
    return Task(
      id: row['id']?.toString(),
      title: row['title']?.toString() ?? 'Sin título',
      description: row['description']?.toString() ?? 'Sin descripción',
      subject: row['subject']?.toString() ?? 'Sin asignatura',
      professor: row['professor']?.toString() ?? 'Sin profesor',
      dueDate: DateTime.fromMillisecondsSinceEpoch(
        (row['due_date'] as num).toInt(),
      ),
      isCompleted: row['is_completed'] as bool? ?? false,
      isSubmitted: row['is_submitted'] as bool? ?? false,
      type: (row['type']?.toString() ?? 'trabajo').toLowerCase(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num).toInt(),
      ),
      tag: row['tag']?.toString(),
      userId: row['user_id']?.toString() ?? '',
      userName: row['user_name']?.toString() ?? 'Usuario',
      careerId: row['career_id']?.toString(),
      collaborators: List<String>.from(row['collaborators'] ?? []),
      // Solo vienen en shared_tasks, y solo si alguien ya editó la tarea.
      updatedByName: (row['updated_by_name'] as String?)?.trim().isEmpty ?? true
          ? null
          : row['updated_by_name'] as String?,
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.tryParse(row['updated_at'].toString()),
    );
  }

  /// Convierte un Subject al formato de columnas de Supabase
  Map<String, dynamic> _subjectToRow(Subject subject) {
    return {
      'name': subject.name,
      'professor': subject.professor,
      'description': subject.description,
      'visibility': subject.visibility.index,
      'allowed_users': subject.allowedUsers,
      'user_id': subject.userId,
      'user_name': subject.userName,
      'created_at': subject.createdAt.millisecondsSinceEpoch,
    };
  }

  /// Convierte una fila de Supabase en un Subject
  Subject _rowToSubject(Map<String, dynamic> row) {
    return Subject(
      id: row['id']?.toString(),
      name: row['name']?.toString() ?? '',
      professor: row['professor']?.toString() ?? '',
      description: row['description']?.toString(),
      visibility: SubjectVisibility.values[row['visibility'] as int? ?? 0],
      allowedUsers: List<String>.from(row['allowed_users'] ?? []),
      userId: row['user_id']?.toString() ?? '',
      userName: row['user_name']?.toString() ?? 'Usuario',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num).toInt(),
      ),
    );
  }

  // ── Membresías de carrera ────────────────────────────────────

  /// Comprueba que las carreras guardadas localmente tengan su membresía en
  /// `user_careers`.
  ///
  /// Antes esta función escribía: hacía upsert en `careers` y se insertaba sola
  /// en `user_careers`. Las dos cosas ya no están permitidas — `careers` es de
  /// escritura exclusiva de administradores y las membresías las crea el RPC
  /// `join_career`, que es el que valida la clave. Si el cliente pudiera
  /// insertarse solo, la clave de carrera no serviría de nada.
  ///
  /// Queda como verificación: si falta una membresía, el usuario tiene que
  /// volver a ingresar la clave de esa carrera.
  Future<void> registerCareerMemberships() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final userCareers = CareerService().getCareers();
    if (userCareers.isEmpty) return;

    try {
      final rows = await _client
          .from('user_careers')
          .select('career_id')
          .eq('user_id', uid);

      final registered = rows
          .map((r) => (r as Map)['career_id'] as String?)
          .whereType<String>()
          .toSet();

      final missing = userCareers
          .where((c) => !registered.contains(c.id))
          .map((c) => c.id)
          .toList();

      if (missing.isNotEmpty) {
        Logger.warning(
          'Carreras locales sin membresía en el servidor: ${missing.join(', ')}. '
          'El usuario debe reingresar la clave de acceso.',
          tag: 'SupabaseDbService',
        );
      }
    } catch (e) {
      Logger.warning(
        'Error verificando carreras del usuario: $e',
        error: e,
        tag: 'SupabaseDbService',
      );
    }
  }

  // ── Helpers de tabla según careerId ─────────────────────────

  bool _isShared(String? careerId) => Careers.isShared(careerId);

  // ── TASKS ────────────────────────────────────────────────────

  /// Crea la tarea directamente en Supabase, sin fallback local. Lanza si falla
  /// (sin conexión, error del servidor, etc.) — quien llame decide qué hacer.
  ///
  /// Importante: si la tarea es de carrera (compartida) y la escritura falla,
  /// NO se reintenta en la tabla personal `tasks` — hacerlo la reclasificaría
  /// silenciosamente como tarea privada y el resto de la carrera dejaría de
  /// verla. Es preferible que falle y se reintente más tarde como compartida.
  Future<String> createTaskRemote(Task task) async {
    final activeCareer = CareerService().getSelectedCareer();
    final effectiveCareerId = (task.careerId != null && task.careerId!.isNotEmpty)
        ? task.careerId
        : activeCareer?.id;

    final updatedTask = task.copyWith(careerId: effectiveCareerId);

    // Registrar membresías de carrera en Supabase antes de insertar para cumplir con las políticas RLS
    await registerCareerMemberships();

    Logger.database('Agregando tarea: ${updatedTask.title}');
    final isSharedTask = _isShared(updatedTask.careerId);
    final table = isSharedTask ? 'shared_tasks' : 'tasks';
    final row = _taskToRow(updatedTask, isShared: isSharedTask);

    if (!isSharedTask) {
      row['user_id'] = _uid;
      row.remove('created_by');
    } else {
      // Para shared_tasks user_id es string (userId del creador)
      row['user_id'] = _uid;
    }

    final result = await _client.from(table).insert(row).select('id').single();
    final newId = result['id'] as String;
    final newTask = updatedTask.copyWith(id: newId);
    await _cache.cacheTask(newTask);
    Logger.database('Tarea agregada exitosamente en $table con ID: $newId');
    return newId;
  }

  /// Crea una tarea. Si falla la escritura remota (sin conexión, error de
  /// servidor), la guarda en caché local con un id temporal y la marca para
  /// sincronizar más tarde — nunca lanza.
  Future<String> addTask(Task task) async {
    try {
      return await createTaskRemote(task);
    } catch (e) {
      Logger.warning(
        'Error guardando tarea en Supabase, guardando en caché local',
        error: e,
        tag: 'SupabaseDbService',
      );
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final newTask = task.copyWith(id: tempId);
      await _cache.cacheTask(newTask);
      await _cache.markPendingSync('task', tempId, 'create');
      return tempId;
    }
  }

  /// Actualiza la tarea directamente en Supabase. Lanza si falla — quien
  /// llame decide qué hacer (usado también por SyncService para reintentos).
  Future<void> updateTaskRemote(Task task) async {
    Logger.database('Actualizando tarea: ${task.id}');
    final isShared = _isShared(task.careerId);
    final primaryTable = isShared ? 'shared_tasks' : 'tasks';
    final secondaryTable = isShared ? 'tasks' : 'shared_tasks';

    // Campos de autoría: identifican a quien CREÓ la tarea, así que una
    // edición no puede tocarlos. Faltaba quitar user_name, y por eso al editar
    // una tarea compartida el nombre del creador quedaba reemplazado por el
    // del editor. En shared_tasks el trigger los preserva igual, pero tampoco
    // hay que mandarlos.
    void stripAuthorFields(Map<String, dynamic> r) {
      r.remove('user_id');
      r.remove('user_name');
      r.remove('created_by');
    }

    final row = _taskToRow(task, isShared: isShared);
    stripAuthorFields(row);

    try {
      await _client.from(primaryTable).update(row).eq('id', task.id!);
    } catch (errPrimary) {
      Logger.warning('Falló update en $primaryTable ($errPrimary), intentando en $secondaryTable', tag: 'SupabaseDbService');
      final secondaryRow = _taskToRow(task, isShared: !isShared);
      stripAuthorFields(secondaryRow);
      await _client.from(secondaryTable).update(secondaryRow).eq('id', task.id!);
    }

    await _cache.cacheTask(task);
    Logger.database('Tarea actualizada exitosamente');
  }

  /// Actualiza una tarea. Si falla la escritura remota, guarda en caché local
  /// y la marca para sincronizar más tarde — nunca lanza.
  Future<void> updateTask(Task task) async {
    if (task.id == null) throw Exception('Task ID is required for update');
    try {
      await updateTaskRemote(task);
    } catch (e) {
      Logger.warning(
        'Error actualizando en Supabase, guardando en caché: $e',
        error: e,
        tag: 'SupabaseDbService',
      );
      await _cache.cacheTask(task);
      await _cache.markPendingSync(
        'task',
        task.id!,
        'update',
        careerId: task.careerId,
      );
    }
  }

  /// Elimina la tarea directamente en Supabase. Lanza si falla.
  Future<void> deleteTaskRemote(String taskId, {String? careerId}) async {
    Logger.database('Eliminando tarea: $taskId');
    final table = _isShared(careerId) ? 'shared_tasks' : 'tasks';
    await _client.from(table).delete().eq('id', taskId);
    await _cache.removeCachedTask(taskId);
    Logger.database('Tarea eliminada exitosamente');
  }

  /// Elimina una tarea. Si falla la escritura remota, la marca para
  /// sincronizar más tarde — nunca lanza.
  Future<void> deleteTask(String taskId, {String? careerId}) async {
    try {
      await deleteTaskRemote(taskId, careerId: careerId);
    } catch (e) {
      Logger.warning(
        'Error eliminando en Supabase, marcando para sync',
        error: e,
        tag: 'SupabaseDbService',
      );
      await _cache.removeCachedTask(taskId);
      await _cache.markPendingSync(
        'task',
        taskId,
        'delete',
        careerId: careerId,
      );
    }
  }

  Future<List<Task>> getTasks({String? careerId}) async {
    try {
      Logger.database(
        'Cargando tareas${careerId != null ? ' para carrera: $careerId' : ''}',
      );

      // Tareas personales
      var query = _client
          .from('tasks')
          .select()
          .eq('user_id', _uid)
          .order('created_at', ascending: false);

      final personalRows = await query;
      final tasks = <Task>[];
      final existingIds = <String>{};

      for (final row in personalRows) {
        try {
          final task = _rowToTask(row);
          if (task.id != null) existingIds.add(task.id!);
          tasks.add(task);
        } catch (e) {
          Logger.error(
            'Error parseando tarea personal: $e',
            error: e,
            tag: 'SupabaseDbService',
          );
        }
      }

      // Tareas compartidas de carreras del usuario
      await registerCareerMemberships();
      final sharedCareerIds = careerId != null
          ? (_isShared(careerId) ? [careerId] : <String>[])
          : CareerService().careerIds.where(_isShared).toList();

      for (final sharedCareerId in sharedCareerIds) {
        try {
          final sharedRows = await _client
              .from('shared_tasks')
              .select()
              .eq('career_id', sharedCareerId)
              .order('created_at', ascending: false);

          for (final row in sharedRows) {
            try {
              final task = _rowToTask(row);
              if (task.id != null && existingIds.contains(task.id)) continue;
              if (task.id != null) existingIds.add(task.id!);
              tasks.add(task);
            } catch (e) {
              Logger.error(
                'Error parseando tarea compartida: $e',
                error: e,
                tag: 'SupabaseDbService',
              );
            }
          }
        } catch (e) {
          Logger.warning(
            'Error cargando tareas compartidas de $sharedCareerId',
            error: e,
            tag: 'SupabaseDbService',
          );
        }
      }

      // Red de seguridad: recuperar tareas compartidas creadas por este usuario
      try {
        final mySharedRows = await _client
            .from('shared_tasks')
            .select()
            .eq('created_by', _uid)
            .order('created_at', ascending: false);

        for (final row in mySharedRows) {
          try {
            final task = _rowToTask(row);
            if (task.id != null && existingIds.contains(task.id)) continue;
            if (task.id != null) existingIds.add(task.id!);
            tasks.add(task);
          } catch (_) {}
        }
      } catch (e) {
        Logger.warning(
          'Error cargando tareas creadas por el usuario en shared_tasks',
          error: e,
          tag: 'SupabaseDbService',
        );
      }

      // Solo mantener tareas temporales pendientes de sincronización local que no estén en la nube
      final cachedTasks = _cache.getCachedTasks();
      for (final cachedTask in cachedTasks) {
        if (cachedTask.id != null &&
            cachedTask.id!.startsWith('temp_') &&
            !existingIds.contains(cachedTask.id)) {
          tasks.add(cachedTask);
          existingIds.add(cachedTask.id!);
        }
      }

      await _cache.replaceCachedTasks(tasks);
      Logger.database('Tareas cargadas: ${tasks.length}');

      // Sincronizar progreso personal
      final uid = currentUser?.id;
      if (uid != null) {
        try {
          await TaskProgressService().syncProgress(uid);
        } catch (e) {
          Logger.warning(
            'Error sincronizando progreso',
            error: e,
            tag: 'SupabaseDbService',
          );
        }
      }

      return applyCurrentUserProgress(tasks);
    } catch (e) {
      Logger.warning(
        'Error cargando desde Supabase, usando caché local',
        error: e,
        tag: 'SupabaseDbService',
      );
      return _cache.getCachedTasks();
    }
  }

  List<Task> applyCurrentUserProgress(List<Task> tasks) {
    final uid = currentUser?.id;
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

  /// Stream de cambios relevantes (tareas personales + compartidas + progreso)
  Stream<void> watchRelevantChanges({String? careerId}) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Stream<void>.error(Exception('Usuario no autenticado'));
    }

    final controller = StreamController<void>.broadcast();

    void emitChange() {
      if (!controller.isClosed) controller.add(null);
    }

    // Escuchar tareas personales
    final personalSub = _client
        .from('tasks')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen((_) => emitChange(), onError: controller.addError);

    // Escuchar tareas compartidas de carreras del usuario
    final sharedCareerIds = careerId != null
        ? (_isShared(careerId) ? [careerId] : <String>[])
        : CareerService().careerIds.where(_isShared).toList();

    final sharedSubs = sharedCareerIds.map((cId) {
      return _client
          .from('shared_tasks')
          .stream(primaryKey: ['id'])
          .eq('career_id', cId)
          .listen((_) => emitChange(), onError: controller.addError);
    }).toList();

    // Escuchar progreso
    final progressSub = _client
        .from('task_progress')
        .stream(primaryKey: ['user_id', 'task_id'])
        .eq('user_id', uid)
        .listen((_) => emitChange(), onError: controller.addError);

    controller.onCancel = () async {
      await personalSub.cancel();
      for (final sub in sharedSubs) {
        await sub.cancel();
      }
      await progressSub.cancel();
    };

    return controller.stream;
  }

  List<Task> getTasksFromCache() => _cache.getCachedTasks();

  Future<void> updateTaskStatus(
    String taskId,
    bool isCompleted,
    bool isSubmitted,
  ) async {
    final uid = currentUser?.id;
    if (uid == null) return;

    final cached = _cache.getCachedTask(taskId);
    final isShared = cached != null && _isShared(cached.careerId);

    if (isShared) {
      Logger.database('Actualizando estado de tarea compartida: $taskId');
      final progressService = TaskProgressService();
      await progressService.setProgress(
        uid,
        taskId,
        isCompleted: isCompleted,
        isSubmitted: isSubmitted,
      );
      final updated = cached.copyWith(
        isCompleted: isCompleted,
        isSubmitted: isSubmitted,
      );
      await _cache.cacheTask(updated);
    } else {
      try {
        Logger.database('Actualizando estado de tarea personal: $taskId');
        await _client.from('tasks').update({
          'is_completed': isCompleted,
          'is_submitted': isSubmitted,
        }).eq('id', taskId).eq('user_id', uid);

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
          tag: 'SupabaseDbService',
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
    final uid = currentUser?.id;
    if (uid == null) return;

    final isShared = _isShared(task.careerId);
    final newCompleted = !task.isCompleted;

    if (isShared) {
      final progressService = TaskProgressService();
      await progressService.setProgress(
        uid,
        task.id!,
        isCompleted: newCompleted,
        isSubmitted: task.isSubmitted,
      );
      final updated = task.copyWith(isCompleted: newCompleted);
      await _cache.cacheTask(updated);
    } else {
      try {
        await _client.from('tasks').update({
          'is_completed': newCompleted,
        }).eq('id', task.id!).eq('user_id', uid);
        final updated = task.copyWith(isCompleted: newCompleted);
        await _cache.cacheTask(updated);
      } catch (e) {
        Logger.warning(
          'Sin conexión al hacer toggle personal, guardando en caché',
          error: e,
          tag: 'SupabaseDbService',
        );
        final updated = task.copyWith(isCompleted: newCompleted);
        await _cache.cacheTask(updated);
        await _cache.markPendingSync('task', task.id!, 'update');
      }
    }
  }

  // ── SUBJECTS ─────────────────────────────────────────────────

  /// Crea la materia directamente en Supabase, sin fallback local. Lanza si falla.
  Future<String> createSubjectRemote(Subject subject) async {
    Logger.database('Agregando materia: ${subject.name}');
    final row = _subjectToRow(subject);
    row['user_id'] = _uid;
    final result =
        await _client.from('subjects').insert(row).select('id').single();
    final newId = result['id'] as String;
    final newSubject = subject.copyWith(id: newId);
    await _cache.cacheSubject(newSubject);
    Logger.database('Materia agregada con ID: $newId');
    return newId;
  }

  /// Crea una materia. Si falla la escritura remota, la guarda en caché local
  /// con un id temporal y la marca para sincronizar más tarde — nunca lanza.
  Future<String> addSubject(Subject subject) async {
    try {
      return await createSubjectRemote(subject);
    } catch (e) {
      Logger.warning(
        'Error guardando materia en Supabase, guardando en caché',
        error: e,
        tag: 'SupabaseDbService',
      );
      final tempId = 'temp_subject_${DateTime.now().millisecondsSinceEpoch}';
      final newSubject = subject.copyWith(id: tempId);
      await _cache.cacheSubject(newSubject);
      await _cache.markPendingSync('subject', tempId, 'create');
      return tempId;
    }
  }

  /// Actualiza la materia directamente en Supabase. Lanza si falla.
  Future<void> updateSubjectRemote(Subject subject) async {
    Logger.database('Actualizando materia: ${subject.id}');
    final row = _subjectToRow(subject);
    row.remove('user_id');
    await _client
        .from('subjects')
        .update(row)
        .eq('id', subject.id!)
        .eq('user_id', _uid);
    await _cache.cacheSubject(subject);
  }

  /// Actualiza una materia. Si falla la escritura remota, guarda en caché
  /// local y la marca para sincronizar más tarde — nunca lanza.
  Future<void> updateSubject(Subject subject) async {
    if (subject.id == null) {
      throw Exception('Subject ID is required for update');
    }
    try {
      await updateSubjectRemote(subject);
    } catch (e) {
      Logger.warning(
        'Error actualizando materia en Supabase, guardando en caché',
        error: e,
        tag: 'SupabaseDbService',
      );
      await _cache.cacheSubject(subject);
      await _cache.markPendingSync('subject', subject.id!, 'update');
    }
  }

  /// Elimina la materia directamente en Supabase. Lanza si falla.
  Future<void> deleteSubjectRemote(String subjectId) async {
    Logger.database('Eliminando materia: $subjectId');
    await _client
        .from('subjects')
        .delete()
        .eq('id', subjectId)
        .eq('user_id', _uid);
    await _cache.removeCachedSubject(subjectId);
  }

  /// Elimina una materia. Si falla la escritura remota, la marca para
  /// sincronizar más tarde — nunca lanza.
  Future<void> deleteSubject(String subjectId) async {
    try {
      await deleteSubjectRemote(subjectId);
    } catch (e) {
      Logger.warning(
        'Error eliminando materia en Supabase',
        error: e,
        tag: 'SupabaseDbService',
      );
      await _cache.removeCachedSubject(subjectId);
      await _cache.markPendingSync('subject', subjectId, 'delete');
    }
  }

  Future<List<Subject>> getSubjects() async {
    try {
      Logger.database('Cargando materias');
      final rows = await _client
          .from('subjects')
          .select()
          .eq('user_id', _uid)
          .order('name');

      final subjects = rows.map(_rowToSubject).toList();
      await _cache.cacheSubjects(subjects);
      Logger.database('Materias cargadas: ${subjects.length}');
      return subjects;
    } catch (e) {
      Logger.warning(
        'Error cargando materias desde Supabase, usando caché',
        error: e,
        tag: 'SupabaseDbService',
      );
      return _cache.getCachedSubjects();
    }
  }

  List<Subject> getSubjectsFromCache() => _cache.getCachedSubjects();

  Future<List<Subject>> getPublicSubjects() async {
    try {
      Logger.database('Cargando materias públicas');
      final rows = await _client
          .from('subjects')
          .select()
          .eq('user_id', _uid)
          .eq('visibility', SubjectVisibility.cursoCompleto.index)
          .order('name');
      return rows.map(_rowToSubject).toList();
    } catch (e) {
      Logger.warning(
        'Error cargando materias públicas',
        error: e,
        tag: 'SupabaseDbService',
      );
      return [];
    }
  }
}
