import 'dart:async';

import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/task_model.dart';
import '../models/subject_model.dart';
import '../models/career_model.dart';
import 'career_service.dart';
import 'encryption_service.dart';
import 'local_cache_service.dart';
import 'task_progress_service.dart';
import 'supabase_service.dart';
import '../utils/hive_box_helper.dart';
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

  /// Nota y comentario del docente pendientes de confirmar en el servidor,
  /// por tarea — mismo patrón que AttendanceService: escritura optimista en
  /// Hive, se reintenta cada vez que se vuelve a pedir la lista. Antes esto
  /// era un RPC-y-listo sin caché: si fallaba (sin conexión a mitad de
  /// clase, el caso normal de un profesor con el celular), la nota se
  /// perdía y había que volver a escribirla.
  Box? _progressPendingBox;
  static const _progressPendingBoxName = 'task_progress_pending_box';

  Future<void> init() async {
    _progressPendingBox = await openHiveBoxSafelyUntyped(
      _progressPendingBoxName,
      cipher: EncryptionService.cipher,
    );
  }

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
      'reminder_minutes': task.reminderMinutes,
    };
    if (isShared) {
      map['created_by'] = _uid;
      map['is_official'] = task.isOfficial;
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
    final effectiveCareerId =
        (task.careerId != null && task.careerId!.isNotEmpty)
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
      final updated = await _client
          .from(table)
          .update(row)
          .eq('id', task.id!)
          .select('id');
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

      final withProgress = applyCurrentUserProgress(tasks);

      // Si nadie de la carrera debe una tarea que YO asigné como docente, la
      // pestaña (pendiente/vencida/entregada) la decide eso y no mi propio
      // task_progress — ver Task.allDelivered. Nunca lanza: sin esto, la
      // tarea sigue clasificándose como hasta ahora.
      try {
        final delivery = await getMyCreatedSharedTasksDeliveryStatus();
        if (delivery.isNotEmpty) {
          return withProgress
              .map(
                (t) => t.id != null && delivery.containsKey(t.id)
                    ? t.copyWith(allDelivered: delivery[t.id])
                    : t,
              )
              .toList();
        }
      } catch (e) {
        Logger.warning(
          'Error consultando entrega de tareas de docente',
          error: e,
          tag: 'SupabaseDbService',
        );
      }

      return withProgress;
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
        teacherComment: progress['teacherComment'] as String?,
        grade: progress['grade'] as String?,
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
        await _cache.cacheTask(
          cached.copyWith(isCompleted: isCompleted, isSubmitted: isSubmitted),
        );
      }
    } else {
      try {
        Logger.database('Actualizando estado de tarea personal: $taskId');
        await _client
            .from('tasks')
            .update({'is_completed': isCompleted, 'is_submitted': isSubmitted})
            .eq('id', taskId)
            .eq('user_id', uid);

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
        await _client
            .from('tasks')
            .update({'is_completed': newCompleted})
            .eq('id', task.id!)
            .eq('user_id', uid);
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

  /// Progreso de cada miembro de la carrera en una tarea compartida: quién la
  /// marcó realizada/enviada y quién no. El RPC en el servidor exige haber
  /// creado la tarea — si no, lanza y no llega ninguna fila; no hay una
  /// política RLS nueva que exponga `task_progress` de otros usuarios.
  ///
  /// Antes de pedir la lista fresca, reintenta la nota/comentario que hayan
  /// quedado pendientes de sincronizar (ver [setTaskFeedback]) y, si alguna
  /// sigue sin poder confirmarse, la deja marcada `pending: true` encima del
  /// valor del servidor en vez de perderla.
  Future<List<Map<String, dynamic>>> getTaskSubmissionStatus(
    String taskId,
  ) async {
    final stillPending = await _flushPendingFeedback(taskId);

    try {
      final rows = await _client.rpc(
        'get_task_submission_status',
        params: {'p_task_id': taskId},
      );
      final list = (rows as List)
          .map(
            (r) => <String, dynamic>{
              ...Map<String, dynamic>.from(r as Map),
              'pending': false,
            },
          )
          .toList();

      for (final entry in stillPending.entries) {
        final idx = list.indexWhere(
          (r) => r['user_id'].toString() == entry.key,
        );
        if (idx >= 0) {
          list[idx] = {
            ...list[idx],
            'teacher_comment': entry.value['teacher_comment'],
            'grade': entry.value['grade'],
            'pending': true,
          };
        }
      }

      await _progressPendingBox?.put(taskId, {'rows': list});
      return list;
    } catch (e) {
      final cached = _readCachedFeedbackRows(taskId);
      if (cached != null) {
        Logger.warning(
          'Sin conexión, usando progreso guardado',
          tag: 'SupabaseDbService',
        );
        return cached;
      }
      rethrow;
    }
  }

  /// Nota y comentario del docente para un alumno en una tarea, guardados
  /// juntos — la UI siempre los edita a la vez. Si no hay conexión, quedan
  /// guardados localmente y se reintentan solos la próxima vez que se pida
  /// [getTaskSubmissionStatus] para esta tarea; antes se perdían sin más si
  /// el RPC fallaba a mitad.
  ///
  /// Devuelve true si quedó confirmado en el servidor, false si quedó
  /// pendiente de sincronizar.
  Future<bool> setTaskFeedback(
    String taskId,
    String studentUserId, {
    required String comment,
    required String grade,
  }) async {
    await _setPendingFeedbackRow(
      taskId,
      studentUserId,
      comment: comment,
      grade: grade,
      pending: true,
    );
    try {
      await _client.rpc(
        'set_task_teacher_comment',
        params: {
          'p_task_id': taskId,
          'p_user_id': studentUserId,
          'p_comment': comment,
        },
      );
      await _client.rpc(
        'set_task_grade',
        params: {
          'p_task_id': taskId,
          'p_user_id': studentUserId,
          'p_grade': grade,
        },
      );
      await _setPendingFeedbackRow(
        taskId,
        studentUserId,
        comment: comment,
        grade: grade,
        pending: false,
      );
      return true;
    } catch (e) {
      Logger.warning(
        'Sin conexión al guardar nota/comentario, queda pendiente de sincronizar',
        error: e,
        tag: 'SupabaseDbService',
      );
      return false;
    }
  }

  /// Reintenta las filas marcadas `pending` para esta tarea. Devuelve las
  /// que siguen sin poder confirmarse (por ejemplo, si seguimos sin red).
  Future<Map<String, Map<String, String?>>> _flushPendingFeedback(
    String taskId,
  ) async {
    final cached = _progressPendingBox?.get(taskId) as Map?;
    if (cached == null) return {};

    final rows = List<Map>.from((cached['rows'] as List?) ?? []);
    final stillPending = <String, Map<String, String?>>{};

    for (final row in rows) {
      if (row['pending'] != true) continue;
      final uid = row['user_id'].toString();
      final comment = row['teacher_comment'] as String?;
      final grade = row['grade'] as String?;
      try {
        await _client.rpc(
          'set_task_teacher_comment',
          params: {
            'p_task_id': taskId,
            'p_user_id': uid,
            'p_comment': comment ?? '',
          },
        );
        await _client.rpc(
          'set_task_grade',
          params: {
            'p_task_id': taskId,
            'p_user_id': uid,
            'p_grade': grade ?? '',
          },
        );
      } catch (_) {
        stillPending[uid] = {'teacher_comment': comment, 'grade': grade};
      }
    }
    return stillPending;
  }

  List<Map<String, dynamic>>? _readCachedFeedbackRows(String taskId) {
    final cached = _progressPendingBox?.get(taskId) as Map?;
    if (cached == null) return null;
    final rows = cached['rows'] as List?;
    if (rows == null) return null;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> _setPendingFeedbackRow(
    String taskId,
    String userId, {
    required String comment,
    required String grade,
    required bool pending,
  }) async {
    final cached = _progressPendingBox?.get(taskId) as Map?;
    final rows = cached != null
        ? List<Map>.from(cached['rows'] as List? ?? [])
        : <Map>[];
    final idx = rows.indexWhere((r) => r['user_id'].toString() == userId);
    final updated = {
      'user_id': userId,
      'teacher_comment': comment,
      'grade': grade,
      'pending': pending,
    };
    if (idx >= 0) {
      rows[idx] = {...rows[idx], ...updated};
    } else {
      rows.add(updated);
    }
    await _progressPendingBox?.put(taskId, {'rows': rows});
  }

  /// Riesgo por alumno en la carrera: tareas oficiales vencidas sin entregar
  /// y porcentaje de asistencia marcada. Regla simple, no analítica ni IA —
  /// el RPC exige ser docente de esa carrera.
  Future<List<Map<String, dynamic>>> getStudentRisk(String careerId) async {
    final rows = await _client.rpc(
      'get_student_risk',
      params: {'p_career_id': careerId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Todas las tareas compartidas de la carrera con el progreso de un
  /// alumno puntual — para la Ficha del alumno del docente.
  Future<List<Map<String, dynamic>>> getStudentTasks(
    String careerId,
    String studentId,
  ) async {
    final rows = await _client.rpc(
      'get_student_tasks',
      params: {'p_career_id': careerId, 'p_student_id': studentId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Por cada tarea compartida que YO creé como docente: si ya nadie de la
  /// carrera se la debe. Ver [Task.allDelivered] y get_my_created_shared_
  /// tasks_status — decide en qué pestaña (pendiente/vencida/entregada) cae
  /// una tarea que el docente asignó, ya que su propio task_progress nunca
  /// se completa (no es él quien la hace).
  Future<Map<String, bool>> getMyCreatedSharedTasksDeliveryStatus() async {
    final rows = await _client.rpc('get_my_created_shared_tasks_status');
    final map = <String, bool>{};
    for (final row in (rows as List)) {
      final id = row['task_id']?.toString();
      if (id != null) map[id] = row['all_delivered'] as bool? ?? false;
    }
    return map;
  }

  /// Una fila por nota puesta en la carrera (de cualquier asignatura, no
  /// solo la que el docente imparte) — para que los docentes se den
  /// feedback entre asignaturas.
  Future<List<Map<String, dynamic>>> getCareerGrades(String careerId) async {
    final rows = await _client.rpc(
      'get_career_grades',
      params: {'p_career_id': careerId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Una fila por (alumno, asignatura) con su % de asistencia en esa
  /// materia — a diferencia de [getStudentRisk], que da un único % por
  /// alumno mezclando toda la carrera.
  Future<List<Map<String, dynamic>>> getCareerAttendanceSummary(
    String careerId,
  ) async {
    final rows = await _client.rpc(
      'get_career_attendance_summary',
      params: {'p_career_id': careerId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Archivos que los alumnos subieron a su área personal (no adjuntos a
  /// ninguna tarea oficial) en las asignaturas que el docente imparte — para
  /// entregas informales que no pasaron por el flujo normal de tareas (p.
  /// ej. trabajo extra ya conversado con el alumno). El RPC exige ser
  /// docente de esa carrera y filtra server-side por [teacher_subjects].
  Future<List<Map<String, dynamic>>> getStudentUploadsForTeachingSubjects(
    String careerId,
  ) async {
    final rows = await _client.rpc(
      'get_student_uploads_for_teaching_subjects',
      params: {'p_career_id': careerId},
    );
    return List<Map<String, dynamic>>.from(rows as List);
  }

  /// Si [subject] tiene un docente asignado en [careerId] — sin decir quién,
  /// solo si existe. Se usa antes de subir un archivo personal para decidir
  /// si conviene abrirlo en Drive ([GoogleDriveService.setLinkViewable]): sin
  /// eso, un docente que ya puede ver la fila en study_files igual se
  /// encuentra con "solicitar acceso al propietario" al intentar abrirlo,
  /// porque drive.file no comparte nada por sí solo.
  Future<bool> subjectHasTeacher(String careerId, String subject) async {
    final result = await _client.rpc(
      'subject_has_teacher',
      params: {'p_career_id': careerId, 'p_subject': subject},
    );
    return result as bool? ?? false;
  }

  // ── SUBJECTS ─────────────────────────────────────────────────

  /// Crea la materia directamente en Supabase, sin fallback local. Lanza si falla.
  Future<String> createSubjectRemote(Subject subject) async {
    Logger.database('Agregando materia: ${subject.name}');
    final row = _subjectToRow(subject);
    row['user_id'] = _uid;
    final result = await _client
        .from('subjects')
        .insert(row)
        .select('id')
        .single();
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
