import 'package:flutter/material.dart';

/// Niveles de visibilidad de una materia.
enum SubjectVisibility {
  soloYo, // Solo el creador puede verla
  cursoCompleto, // Todos pueden verla
  seleccionar, // Elegir usuarios específicos
}

/// Modelo de materia académica con validaciones.
class Subject {
  String? id;
  String name;
  String professor;
  String? description;
  SubjectVisibility visibility;
  List<String>
  allowedUsers; // IDs de usuarios permitidos si visibility = seleccionar
  String userId;
  String userName;
  DateTime createdAt;

  /// Si es falsa, la materia no se ofrece para tareas ni reuniones nuevas —
  /// pero sigue disponible en Archivos/Material docente, para poder seguir
  /// organizando ahí lo de semestres anteriores. Solo aplica a las materias
  /// predefinidas de una carrera; las propias del usuario no la usan.
  bool isActive;

  /// Etiqueta libre ("Segundo Año · Sem. IV") para que el admin ubique de un
  /// vistazo a qué semestre pertenece una materia predefinida, sin tener que
  /// adivinar por el nombre. Solo se muestra en el panel de administración;
  /// no afecta selectores ni validación del servidor.
  String? semester;

  Subject({
    this.id,
    required this.name,
    required this.professor,
    this.description,
    this.visibility = SubjectVisibility.soloYo,
    this.allowedUsers = const [],
    required this.userId,
    required this.userName,
    required this.createdAt,
    this.isActive = true,
    this.semester,
  }) {
    _validate();
  }

  /// Valida los datos de la materia y lanza excepción si son inválidos.
  void _validate() {
    if (name.trim().isEmpty) {
      throw ArgumentError('El nombre de la materia es obligatorio');
    }
    if (name.length > 100) {
      throw ArgumentError('El nombre no puede exceder 100 caracteres');
    }
    if (professor.trim().isEmpty) {
      throw ArgumentError('El nombre del profesor es obligatorio');
    }
    if (professor.length > 150) {
      throw ArgumentError(
        'El nombre del profesor no puede exceder 150 caracteres',
      );
    }
    if (description != null && description!.length > 1000) {
      throw ArgumentError('La descripción no puede exceder 1000 caracteres');
    }
    if (userId.trim().isEmpty) {
      throw ArgumentError('El ID de usuario es obligatorio');
    }
    if (userName.trim().isEmpty) {
      throw ArgumentError('El nombre de usuario es obligatorio');
    }
    // Validar que allowedUsers solo se use cuando visibility = seleccionar
    if (visibility != SubjectVisibility.seleccionar &&
        allowedUsers.isNotEmpty) {
      throw ArgumentError(
        'allowedUsers solo se permite cuando visibility = seleccionar',
      );
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'professor': professor,
      'description': description,
      'visibility': visibility.index,
      'allowedUsers': allowedUsers,
      'userId': userId,
      'userName': userName,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'isActive': isActive,
      'semester': semester,
    };
  }

  factory Subject.fromMap(Map<String, dynamic> map, [String? id]) {
    return Subject(
      id: id ?? map['id']?.toString(),
      name: map['name'] ?? '',
      professor: map['professor'] ?? '',
      description: map['description'],
      visibility: SubjectVisibility.values[map['visibility'] ?? 0],
      allowedUsers: List<String>.from(map['allowedUsers'] ?? []),
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Usuario',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isActive: map['isActive'] as bool? ?? true,
      semester: map['semester']?.toString(),
    );
  }

  Subject copyWith({
    String? id,
    String? name,
    String? professor,
    String? description,
    SubjectVisibility? visibility,
    List<String>? allowedUsers,
    String? userId,
    String? userName,
    DateTime? createdAt,
    bool? isActive,
    String? semester,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      professor: professor ?? this.professor,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      allowedUsers: allowedUsers ?? this.allowedUsers,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      semester: semester ?? this.semester,
    );
  }

  String get visibilityText {
    switch (visibility) {
      case SubjectVisibility.soloYo:
        return 'Solo yo';
      case SubjectVisibility.cursoCompleto:
        return 'Curso completo';
      case SubjectVisibility.seleccionar:
        return 'Elegir usuarios';
    }
  }

  IconData get visibilityIcon {
    switch (visibility) {
      case SubjectVisibility.soloYo:
        return Icons.lock;
      case SubjectVisibility.cursoCompleto:
        return Icons.public;
      case SubjectVisibility.seleccionar:
        return Icons.people;
    }
  }
}
