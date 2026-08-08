/// Modelo de tarea académica con validaciones.
class Task {
  String? id;
  String title;
  String description;
  String subject;
  String professor;
  DateTime dueDate;
  bool isCompleted;
  bool isSubmitted;
  String type;
  DateTime createdAt;
  String? tag;
  String userId;
  String userName;

  /// Carrera a la que pertenece la tarea. Ahora es obligatoria: no se puede
  /// usar la app sin estar en alguna, y sirve para acotar las asignaturas
  /// que se ofrecen.
  String? careerId;

  /// Si la ve toda la carrera o solo su autor.
  ///
  /// Antes esto se deducía de que [careerId] estuviera lleno: cualquier tarea
  /// con carrera se publicaba al grupo. Como la carrera se heredaba en
  /// silencio de la que estuviera activa, se podía terminar publicando una
  /// tarea sin haberlo decidido nunca — y sin forma de tener una tarea
  /// privada estando dentro de una carrera.
  ///
  /// Ahora son dos cosas separadas: la carrera dice *de qué* es la tarea,
  /// esto dice *quién la ve*. Por defecto privada, igual que las reuniones.
  bool isShared;
  List<String>
  collaborators; // IDs de usuarios con los que se comparte la tarea

  /// Nombre de quien editó la tarea por última vez, y cuándo. Solo aplica a
  /// tareas compartidas de carrera, que cualquier miembro puede editar.
  ///
  /// Los estampa el trigger `shared_tasks_stamp_author` en Supabase, no el
  /// cliente: si los mandara la app, cualquiera podría atribuirle una edición
  /// a otra persona. Son de solo lectura, por eso no van en [toMap].
  String? updatedByName;
  DateTime? updatedAt;

  Task({
    this.id,
    required this.title,
    required this.description,
    required this.subject,
    required this.professor,
    required this.dueDate,
    this.isCompleted = false,
    this.isSubmitted = false,
    this.type = 'trabajo',
    required this.createdAt,
    this.tag,
    required this.userId,
    required this.userName,
    this.careerId,
    this.isShared = false,
    this.collaborators = const [],
    this.updatedByName,
    this.updatedAt,
  }) {
    _validate();
  }

  /// Tipos que se ofrecen al crear o editar una tarea, en el orden en que
  /// aparecen en el desplegable. Es la lista canónica: [acceptedTypes] la
  /// incluye y le suma las variantes viejas.
  static const List<String> selectableTypes = [
    'trabajo',
    'resumen',
    'estudio',
    'prueba',
    'examen',
    'laboratorio',
    'lectura',
    'ensayo',
    'presentación',
    'otro',
  ];

  /// Tipos que la validación acepta. Además de los seleccionables incluye
  /// 'presentacion' sin tilde, que quedó en tareas creadas por versiones
  /// anteriores: rechazarla ahora rompería al leerlas.
  static const List<String> acceptedTypes = [
    ...selectableTypes,
    'presentacion',
  ];

  /// Valida los datos de la tarea y lanza excepción si son inválidos.
  void _validate() {
    if (title.trim().isEmpty) {
      throw ArgumentError('El título de la tarea es obligatorio');
    }
    if (title.length > 200) {
      throw ArgumentError('El título no puede exceder 200 caracteres');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError('La descripción de la tarea es obligatoria');
    }
    if (description.length > 2000) {
      throw ArgumentError('La descripción no puede exceder 2000 caracteres');
    }
    if (subject.trim().isEmpty) {
      throw ArgumentError('La materia es obligatoria');
    }
    if (professor.trim().isEmpty) {
      throw ArgumentError('El profesor es obligatorio');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError('El ID de usuario es obligatorio');
    }
    if (userName.trim().isEmpty) {
      throw ArgumentError('El nombre de usuario es obligatorio');
    }
    // Validar que la fecha de entrega no sea muy antigua (máximo 5 años atrás)
    final fiveYearsAgo = DateTime.now().subtract(const Duration(days: 5 * 365));
    if (dueDate.isBefore(fiveYearsAgo)) {
      throw ArgumentError('La fecha de entrega no puede ser tan antigua');
    }
    // Validar tipos de tarea permitidos
    if (!acceptedTypes.contains(type.toLowerCase())) {
      throw ArgumentError('Tipo de tarea no válido: $type');
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'subject': subject,
      'professor': professor,
      'dueDate': dueDate.millisecondsSinceEpoch,
      'isCompleted': isCompleted,
      'isSubmitted': isSubmitted,
      'type': type,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'tag': tag,
      'userId': userId,
      'userName': userName,
      'careerId': careerId,
      'isShared': isShared,
      'collaborators': collaborators,
      // Solo para el caché local: al servidor no se mandan (los pone el
      // trigger), pero sin esto la autoría desaparecería estando offline.
      'updatedByName': updatedByName,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
    };
  }

  /// Lee un mapa venga de donde venga: de la caché de Hive (`camelCase`) o de
  /// una fila de Supabase (`snake_case`).
  ///
  /// Eran dos lectores paralelos —éste y `_rowToTask` en SupabaseDbService—
  /// con los mismos campos escritos dos veces y los mismos valores por defecto
  /// repetidos. Arreglar algo en uno y olvidarse del otro era cuestión de
  /// tiempo; de hecho ya diferían: uno decía "Sin título" y el otro "Tarea sin
  /// título".
  ///
  /// [isShared] fuerza el valor de [Task.isShared] cuando quien llama ya lo
  /// sabe por otra vía — leer de `shared_tasks` implica que está compartida,
  /// esté o no la columna en la fila.
  factory Task.fromMap(
    Map<String, dynamic> map, [
    String? id,
    bool? isShared,
  ]) {
    // Cada campo se busca primero con su nombre de caché y después con el de
    // la base. `??` no sirve acá: un false o un 0 legítimos harían caer al
    // segundo nombre.
    Object? campo(String cache, String columna) =>
        map.containsKey(cache) ? map[cache] : map[columna];

    String texto(String cache, String columna) =>
        campo(cache, columna)?.toString().trim() ?? '';

    final title = texto('title', 'title');
    final description = texto('description', 'description');
    final subject = texto('subject', 'subject');
    final professor = texto('professor', 'professor');
    final userId = texto('userId', 'user_id');
    final userName = texto('userName', 'user_name');
    final dueDate = campo('dueDate', 'due_date');
    final createdAt = campo('createdAt', 'created_at');

    // Validar tipos de datos críticos
    if (dueDate is! num) {
      throw ArgumentError('dueDate debe ser un número (milisegundos), se recibió: ${dueDate.runtimeType}');
    }
    if (createdAt is! num) {
      throw ArgumentError('createdAt debe ser un número (milisegundos), se recibió: ${createdAt.runtimeType}');
    }

    // updatedAt llega en milisegundos desde la caché y como texto ISO desde
    // Supabase, porque allá la columna es TIMESTAMPTZ.
    final updatedAtRaw = campo('updatedAt', 'updated_at');
    final updatedByName = texto('updatedByName', 'updated_by_name');

    return Task(
      id: id ?? map['id']?.toString(),
      title: title.isEmpty ? 'Tarea sin título' : title,
      description: description.isEmpty ? 'Sin descripción' : description,
      subject: subject.isEmpty ? 'Sin asignatura' : subject,
      professor: professor.isEmpty ? 'Sin profesor' : professor,
      dueDate: DateTime.fromMillisecondsSinceEpoch(dueDate.toInt()),
      isCompleted: campo('isCompleted', 'is_completed') as bool? ?? false,
      isSubmitted: campo('isSubmitted', 'is_submitted') as bool? ?? false,
      type: (campo('type', 'type')?.toString() ?? 'trabajo').toLowerCase(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt.toInt()),
      tag: campo('tag', 'tag')?.toString(),
      userId: userId.isEmpty ? 'unknown' : userId,
      userName: userName.isEmpty ? 'Usuario desconocido' : userName,
      careerId: campo('careerId', 'career_id')?.toString(),
      isShared: isShared ?? campo('isShared', 'is_shared') as bool? ?? false,
      collaborators:
          List<String>.from(campo('collaborators', 'collaborators') as List? ?? []),
      updatedByName: updatedByName.isEmpty ? null : updatedByName,
      updatedAt: updatedAtRaw is num
          ? DateTime.fromMillisecondsSinceEpoch(updatedAtRaw.toInt())
          : DateTime.tryParse(updatedAtRaw?.toString() ?? ''),
    );
  }

  Task copyWith({
    String? id,
    String? title,
    String? description,
    String? subject,
    String? professor,
    DateTime? dueDate,
    bool? isCompleted,
    bool? isSubmitted,
    String? type,
    DateTime? createdAt,
    String? tag,
    String? userId,
    String? userName,
    String? careerId,
    bool? isShared,
    List<String>? collaborators,
    String? updatedByName,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      subject: subject ?? this.subject,
      professor: professor ?? this.professor,
      dueDate: dueDate ?? this.dueDate,
      isCompleted: isCompleted ?? this.isCompleted,
      isSubmitted: isSubmitted ?? this.isSubmitted,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      tag: tag ?? this.tag,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      careerId: careerId ?? this.careerId,
      isShared: isShared ?? this.isShared,
      collaborators: collaborators ?? this.collaborators,
      updatedByName: updatedByName ?? this.updatedByName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  TaskUrgency getUrgency() {
    final now = DateTime.now();
    final difference = dueDate.difference(now);

    // Si está completada y enviada, siempre es "completed" (gris)
    if (isCompleted && isSubmitted) {
      return TaskUrgency.completed;
    }

    if (now.isAfter(dueDate)) {
      return TaskUrgency.overdue;
    } else if (difference.inDays >= 7) {
      return TaskUrgency.low;
    } else if (difference.inDays >= 3) {
      return TaskUrgency.medium;
    } else if (difference.inDays >= 1) {
      return TaskUrgency.high;
    } else {
      return TaskUrgency.urgent;
    }
  }

  bool needsSubmittedMarker() {
    return isCompleted && !isSubmitted;
  }
}

enum TaskUrgency { low, medium, high, urgent, overdue, completed }
