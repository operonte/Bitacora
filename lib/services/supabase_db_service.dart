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

/// La escritura llegó al servidor y fue rechazada: la fila no existe o las
/// políticas RLS no dejan tocarla.
///
/// Se distingue de un fallo de red a propósito. Un corte de conexión se
/// reintenta más tarde; esto no — reintentarlo dará exactamente el mismo
/// resultado, así que no se encola y se le informa al usuario.
class TaskWriteRejectedException implements Exception {
  TaskWriteRejectedException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Servicio de base de datos usando Supabase.
///
/// Consultas a Supabase (PostgreSQL + RLS) con patrón offline-first: Hive es
/// la caché local y se pinta desde ahí antes de ir a la red.
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

  /// Convierte una fila de Supabase en un Task.
  ///
  /// [isShared] lo decide la tabla de origen, no el contenido de la fila: una
  /// tarea que vive en shared_tasks está compartida por definición.
  ///
  /// `Task.fromMap` entiende tanto el formato de la caché como el de las
  /// columnas de Supabase, así que acá ya no hay una segunda copia de los
  /// mismos campos con sus propios valores por defecto.
  Task _rowToTask(Map<String, dynamic> row, {required bool isShared}) =>
      Task.fromMap(row, row['id']?.toString(), isShared);

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

  // ── Helpers de tabla según careerId ─────────────────────────

  /// Nombre de la tabla donde vive una tarea según quién puede verla.
  String _tableFor({required bool isShared}) =>
      isShared ? 'shared_tasks' : 'tasks';

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

    Logger.database('Agregando tarea: ${updatedTask.title}');
    final isSharedTask = updatedTask.isShared;
    final table = _tableFor(isShared: isSharedTask);
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
    final isShared = task.isShared;
    final primaryTable = _tableFor(isShared: isShared);
    final secondaryTable = _tableFor(isShared: !isShared);

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

    // El `.select()` no es decorativo: PostgREST NO lanza cuando un update no
    // toca ninguna fila — si RLS filtra la fila, responde 200 con la lista
    // vacía. Sin comprobar cuántas filas volvieron, una edición que el
    // servidor rechazó se guardaba en caché y la pantalla decía "✓ Tarea
    // actualizada"; el cambio desaparecía en la siguiente sincronización.
    Future<int> updateIn(String table, {required bool asShared}) async {
      final row = _taskToRow(task, isShared: asShared);
      stripAuthorFields(row);
      final updated =
          await _client.from(table).update(row).eq('id', task.id!).select('id');
      return (updated as List).length;
    }

    var affected = await updateIn(primaryTable, asShared: isShared);

    if (affected == 0) {
      // La tarea puede estar en la otra tabla: una creada sin carrera activa
      // vive en `tasks`, y al editarla con una carrera seleccionada su
      // el interruptor de compartir cambió y ahora le toca la otra tabla.
      // Antes esto se descubría por excepción; ahora, por filas afectadas.
      Logger.warning(
        'La tarea ${task.id} no está en $primaryTable, intentando en $secondaryTable',
        tag: 'SupabaseDbService',
      );
      affected = await updateIn(secondaryTable, asShared: !isShared);
    }

    if (affected == 0) {
      throw TaskWriteRejectedException(
        'No se pudo guardar la tarea: ya no existe o no tienes permiso para '
        'editarla.',
      );
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
    } on TaskWriteRejectedException {
      // No se encola: el servidor ya decidió que no. Se propaga para que la
      // pantalla lo diga en vez de fingir que guardó.
      rethrow;
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
        isShared: task.isShared,
      );
    }
  }

  /// Elimina la tarea directamente en Supabase. Lanza si falla.
  ///
  /// [isShared] indica en qué tabla vive. Si no se sabe (una tarea que ya no
  /// está en caché), se intenta en las dos: borrar de más no rompe nada,
  /// porque el id solo existe en una.
  Future<void> deleteTaskRemote(String taskId, {bool? isShared}) async {
    Logger.database('Eliminando tarea: $taskId');
    final tablas = isShared == null
        ? const ['tasks', 'shared_tasks']
        : [_tableFor(isShared: isShared)];
    for (final table in tablas) {
      await _client.from(table).delete().eq('id', taskId);
    }
    await _cache.removeCachedTask(taskId);
    Logger.database('Tarea eliminada exitosamente');
  }

  /// Elimina una tarea. Si falla la escritura remota, la marca para
  /// sincronizar más tarde — nunca lanza.
  Future<void> deleteTask(String taskId, {bool? isShared}) async {
    try {
      await deleteTaskRemote(taskId, isShared: isShared);
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
        isShared: isShared,
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
          final task = _rowToTask(row, isShared: false);
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

      // Tareas compartidas.
      //
      // Una sola consulta, sin filtro por carrera: la política
      // shared_tasks_member ya devuelve exactamente las de las carreras a las
      // que el usuario pertenece más las que creó él. Antes se hacía una
      // consulta por carrera y otra más de "red de seguridad" por created_by,
      // o sea reimplementar en el cliente el filtro que el servidor ya aplica.
      //
      // [careerId] sigue acotando en memoria cuando se pide una carrera
      // puntual, que es lo único que ese parámetro necesitaba.
      // Si la lectura de compartidas falla, la caché NO se reemplaza: un corte
      // de red de dos segundos vaciaba la caja y borraba todas las tareas de
      // carrera hasta la siguiente sincronización exitosa.
      var sharedFetchFailed = false;

      try {
        final sharedRows = await _client
            .from('shared_tasks')
            .select()
            .order('created_at', ascending: false);

        for (final row in sharedRows) {
          try {
            final task = _rowToTask(row, isShared: true);
            if (careerId != null && task.careerId != careerId) continue;
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
        sharedFetchFailed = true;
        Logger.warning(
          'Error cargando tareas compartidas',
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

      if (sharedFetchFailed) {
        // Fusionar en vez de reemplazar: lo que no se pudo leer sigue en la
        // caja y el usuario conserva sus tareas.
        await _cache.cacheTasks(tasks);
        // Se devuelve la unión de lo leído y lo cacheado, para no dejar la
        // pantalla más vacía de lo que estaba antes de refrescar.
        for (final cachedTask in cachedTasks) {
          if (cachedTask.id != null && !existingIds.contains(cachedTask.id)) {
            tasks.add(cachedTask);
            existingIds.add(cachedTask.id!);
          }
        }
      } else {
        await _cache.replaceCachedTasks(tasks);
      }
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
        ? (Careers.isShared(careerId) ? [careerId] : <String>[])
        : CareerService().careerIds.where(Careers.isShared).toList();

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
    final isShared = cached?.isShared ?? false;

    if (isShared) {
      Logger.database('Actualizando estado de tarea compartida: $taskId');
      final progressService = TaskProgressService();
      await progressService.setProgress(
        uid,
        taskId,
        isCompleted: isCompleted,
        isSubmitted: isSubmitted,
      );
      if (cached != null) {
        await _cache.cacheTask(cached.copyWith(
          isCompleted: isCompleted,
          isSubmitted: isSubmitted,
        ));
      }
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

    final isShared = task.isShared;
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
}
