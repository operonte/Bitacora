import '../subject_model.dart';

/// Modelo de carrera académica
class Career {
  final String id;
  final String name;
  final String accessKey;
  final List<Subject> predefinedSubjects;
  final String? description;

  const Career({
    required this.id,
    required this.name,
    required this.accessKey,
    required this.predefinedSubjects,
    this.description,
  });

  Career copyWith({
    String? id,
    String? name,
    String? accessKey,
    List<Subject>? predefinedSubjects,
    String? description,
  }) {
    return Career(
      id: id ?? this.id,
      name: name ?? this.name,
      accessKey: accessKey ?? this.accessKey,
      predefinedSubjects: predefinedSubjects ?? this.predefinedSubjects,
      description: description ?? this.description,
    );
  }
}

/// Carreras predefinidas
class Careers {
  static List<Career> all = [
    Career(
      id: 'teologia',
      name: 'Teología',
      accessKey: 'teologia2026',
      predefinedSubjects: [
        Subject(
          id: 'griego',
          name: 'Griego',
          professor: 'Dr. Daniel Godoy',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'hebreo',
          name: 'Hebreo',
          professor: 'Lic. Hemir Ochoa',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'contexto_at',
          name: 'Contexto literario del antiguo testamento',
          professor: 'Dr. Daniel Godoy',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'hermeneutica',
          name: 'Hermenéutica bíblica',
          professor: 'Lic. Carlos Camaño',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'metodologia',
          name: 'Metodología de estudio bíblico',
          professor: 'Lic. Carlos Camaño',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'historia_iglesia',
          name: 'Introducción a la historia de la iglesia',
          professor: 'Mg. Cecilia Castillo',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'historia_israel',
          name: 'Historia de Israel',
          professor: 'Mg. Jaime Alarcon',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
        Subject(
          id: 'comunicacion',
          name: 'Comunicación y redacción',
          professor: 'Dr. Patricio Abarca',
          userId: 'system',
          userName: 'Sistema',
          createdAt: DateTime.now(),
        ),
      ],
    ),
  ];

  /// Busca carrera por clave de acceso
  static Career? findByAccessKey(String accessKey) {
    try {
      return all.firstWhere((career) => career.accessKey == accessKey);
    } catch (e) {
      return null;
    }
  }

  /// Obtiene lista de nombres de carreras
  static List<String> get careerNames => all.map((c) => c.name).toList();
}
