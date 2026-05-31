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
  String? careerId; // Nuevo campo para filtrar por carrera
  List<String>
  collaborators; // IDs de usuarios con los que se comparte la tarea

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
    this.collaborators = const [],
  }) {
    _validate();
  }

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
    final validTypes = [
      'trabajo',
      'examen',
      'laboratorio',
      'lectura',
      'otro',
      'presentación',
      'presentacion',
      'resumen',
      'estudio',
      'prueba',
      'ensayo',
    ];
    if (!validTypes.contains(type.toLowerCase())) {
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
      'collaborators': collaborators,
    };
  }

  factory Task.fromMap(Map<String, dynamic> map, [String? id]) {
    return Task(
      id: id ?? map['id']?.toString(),
      title: map['title'],
      description: map['description'],
      subject: map['subject'],
      professor: map['professor'],
      dueDate: DateTime.fromMillisecondsSinceEpoch(map['dueDate']),
      isCompleted: map['isCompleted'] ?? false,
      isSubmitted: map['isSubmitted'] ?? false,
      type: map['type'] ?? 'trabajo',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt']),
      tag: map['tag'],
      userId: map['userId'],
      userName: map['userName'],
      careerId: map['careerId'],
      collaborators: List<String>.from(map['collaborators'] ?? []),
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
    List<String>? collaborators,
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
      collaborators: collaborators ?? this.collaborators,
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
