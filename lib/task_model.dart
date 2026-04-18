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
  });

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
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Usuario',
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
