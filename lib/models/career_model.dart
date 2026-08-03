import '../models/subject_model.dart';

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
  /// Carreras definidas en el código (siempre disponibles, incluso offline).
  static final List<Career> _predefined = [
    Career(
      id: 'teologia',
      name: 'Teología',
      // Vacía a propósito: la clave real vive hasheada en Supabase
      // (career_access_keys) y se valida con el RPC join_career. Ponerla acá
      // la publica en el repo y en cada APK.
      accessKey: '',
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

  /// Carreras creadas desde el panel de administración (colección `careers`
  /// en Firestore). Se cargan en runtime con [CareerService.loadRemoteCareers].
  static List<Career> remote = [];

  /// Carreras definidas en el código (solo lectura).
  static List<Career> get predefined => List.unmodifiable(_predefined);

  /// Todas las carreras conocidas: si existen en Supabase (remote), esa versión sustituye a la predefinida.
  static List<Career> get all {
    final Map<String, Career> map = {};
    for (final c in _predefined) {
      map[c.id] = c;
    }
    for (final c in remote) {
      map[c.id] = c;
    }
    return map.values.toList();
  }

  /// Busca carrera por clave de acceso entre las carreras ya conocidas.
  ///
  /// Solo sirve para carreras que el usuario ya tiene guardadas localmente con
  /// su clave. Las claves nuevas se validan contra el servidor
  /// ([CareerService.validateAccessKey]); acá no hay nada que validar porque
  /// el cliente ya no guarda las claves de las carreras a las que no pertenece.
  static Career? findByAccessKey(String accessKey) {
    // Sin esta guarda, una clave vacía calzaría con cualquier carrera cuyo
    // accessKey también esté vacío, que ahora son casi todas.
    if (accessKey.isEmpty) return null;
    try {
      return all.firstWhere((career) => career.accessKey == accessKey);
    } catch (e) {
      return null;
    }
  }

  /// Busca carrera por id. Devuelve null si no existe.
  static Career? findById(String? id) {
    if (id == null || id.isEmpty) return null;
    try {
      return all.firstWhere((career) => career.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Nombre legible de la carrera para mostrar en la UI, o null si no se
  /// puede resolver el [careerId].
  static String? nameForId(String? careerId) => findById(careerId)?.name;

  /// Obtiene lista de nombres de carreras
  static List<String> get careerNames => all.map((c) => c.name).toList();

  /// Indica si las tareas de [careerId] se almacenan en una colección
  /// compartida (de grupo) en vez de la colección personal del usuario.
  ///
  /// Toda carrera/grupo es compartida: cualquier tarea asociada a una carrera
  /// (careerId no vacío) se comparte entre los miembros de esa carrera. Solo
  /// las tareas sin carrera (careerId nulo/vacío) son privadas del usuario.
  static bool isShared(String? careerId) =>
      careerId != null && careerId.isNotEmpty;
}
