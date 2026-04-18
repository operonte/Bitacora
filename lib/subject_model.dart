import 'package:flutter/material.dart';

enum SubjectVisibility {
  soloYo,        // Solo el creador puede verla
  cursoCompleto, // Todos pueden verla
  seleccionar,   // Elegir usuarios específicos
}

class Subject {
  String? id;
  String name;
  String professor;
  String? description;
  SubjectVisibility visibility;
  List<String> allowedUsers; // IDs de usuarios permitidos si visibility = seleccionar
  String userId;
  String userName;
  DateTime createdAt;

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
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'professor': professor,
      'description': description,
      'visibility': visibility.index,
      'allowedUsers': allowedUsers,
      'userId': userId,
      'userName': userName,
      'createdAt': createdAt.millisecondsSinceEpoch,
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
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? DateTime.now().millisecondsSinceEpoch),
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
