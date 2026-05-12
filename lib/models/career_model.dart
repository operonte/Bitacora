/// Modelo de carrera académica
class Career {
  final String id;
  final String name;
  final String accessKey;
  final List<String> predefinedSubjects;
  
  const Career({
    required this.id,
    required this.name,
    required this.accessKey,
    required this.predefinedSubjects,
  });
}

/// Carreras predefinidas
class Careers {
  static const List<Career> all = [
    Career(
      id: 'teologia',
      name: 'Teología',
      accessKey: 'teologia2026',
      predefinedSubjects: [
        'Contexto Literario del Antiguo Testamento',
        'Hermenéutica Bíblica',
        'Metodología del Estudio Bíblico',
        'Introducción a la Historia de la Iglesia I',
        'Historia de Israel I',
        'Comunicaciones y Redacción',
        'Hebreo Bíblico I',
        'Griego 1 (Dr. Daniel Godoy)',
      ],
    ),
    Career(
      id: 'primero_medio_a',
      name: 'Primero Medio A',
      accessKey: 'primero_medio_a',
      predefinedSubjects: [
        'Lenguaje y Comunicación',
        'Matemáticas',
        'Historia, Geografía y Ciencias Sociales',
        'Ciencias Naturales',
        'Inglés',
        'Educación Física y Salud',
        'Artes Visuales',
        'Música',
        'Orientación',
      ],
    ),
    Career(
      id: 'octavo_a',
      name: 'Octavo A',
      accessKey: 'octavo_a',
      predefinedSubjects: [
        'Lenguaje y Comunicación',
        'Matemática',
        'Ciencias Naturales',
        'Historia, Geografía y Ciencias Sociales',
        'Inglés',
        'Educación Física y Salud',
        'Artes Visuales',
        'Música',
        'Tecnología',
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
