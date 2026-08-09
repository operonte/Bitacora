import '../models/career_model.dart';
import '../models/study_file_model.dart';
import '../services/google_drive_service.dart' show normalizeFolderName;

/// A qué carrera, asignatura y categoría corresponde un archivo, deducido de
/// la carpeta de Drive donde está.
class DriveFileLocation {
  final String careerId;
  final String careerName;
  final String subject;
  final String category;

  const DriveFileLocation({
    required this.careerId,
    required this.careerName,
    required this.subject,
    required this.category,
  });
}

/// Por qué un archivo encontrado en Drive no se puede registrar.
///
/// No son fallos de la app: son carpetas que la persona armó a mano y que no
/// calzan con la estructura. Se distinguen para poder decirle **qué** arreglar
/// en vez de que el archivo desaparezca sin explicación.
enum DriveLocationProblem {
  /// Suelto en `Bitácora/`, o en el esquema plano viejo `Bitácora/<asignatura>`:
  /// no hay carpeta de carrera de la que deducirla.
  sinCarrera,

  /// La primera carpeta no corresponde a ninguna carrera del usuario.
  carreraDesconocida,

  /// La segunda carpeta no es una asignatura de esa carrera.
  asignaturaDesconocida,
}

/// Resultado de clasificar: o ubicación, o el motivo por el que no se pudo.
class DriveLocationResult {
  final DriveFileLocation? location;
  final DriveLocationProblem? problem;

  const DriveLocationResult.ok(DriveFileLocation this.location)
      : problem = null;
  const DriveLocationResult.rechazado(DriveLocationProblem this.problem)
      : location = null;

  bool get isOk => location != null;
}

/// Nombre de la subcarpeta de material docente, tal como la crea la app.
const String _materialDocenteFolder = 'Material docente';

/// Deduce carrera, asignatura y categoría de la ruta de un archivo dentro de
/// la carpeta Bitácora.
///
/// [segments] es la ruta **relativa a la raíz Bitácora**: para
/// `Bitácora/Teología/Hebreo II/archivo.pdf` son `['Teología', 'Hebreo II']`.
///
/// La estructura que crea la app es la misma que se lee acá:
/// ```
/// Bitácora/<carrera>/<asignatura>/                  → trabajo
/// Bitácora/<carrera>/<asignatura>/Material docente/ → guia
/// ```
///
/// Rechaza en vez de adivinar. La base exige (migración 16) que la asignatura
/// pertenezca a la carrera, así que inventar un valor solo cambiaría un aviso
/// claro por un INSERT rechazado a mitad de la sincronización.
DriveLocationResult classifyDrivePath(
  List<String> segments,
  List<Career> careers,
) {
  // Sin carpeta de carrera no hay nada que deducir. Un solo segmento es el
  // esquema plano de versiones anteriores (`Bitácora/<asignatura>`), que
  // tampoco dice a qué carrera pertenece.
  if (segments.length < 2) {
    return const DriveLocationResult.rechazado(DriveLocationProblem.sinCarrera);
  }

  final carreraBuscada = normalizeFolderName(segments[0]);
  Career? carrera;
  for (final c in careers) {
    if (normalizeFolderName(c.name) == carreraBuscada) {
      carrera = c;
      break;
    }
  }
  if (carrera == null) {
    return const DriveLocationResult.rechazado(
      DriveLocationProblem.carreraDesconocida,
    );
  }

  final asignaturaBuscada = normalizeFolderName(segments[1]);
  String? asignatura;
  for (final s in carrera.predefinedSubjects) {
    if (normalizeFolderName(s.name) == asignaturaBuscada) {
      // Se guarda el nombre canónico de la carrera, no el de la carpeta: si
      // alguien escribió "hebreo ii" a mano, la fila queda igual que las que
      // crea la app y el trigger de la base la acepta.
      asignatura = s.name;
      break;
    }
  }
  if (asignatura == null) {
    return const DriveLocationResult.rechazado(
      DriveLocationProblem.asignaturaDesconocida,
    );
  }

  // Cualquier nivel por debajo de la asignatura que se llame "Material
  // docente" marca la categoría; el resto de la profundidad se ignora, para
  // que subcarpetas propias del usuario no dejen sus archivos fuera.
  final esGuia = segments
      .skip(2)
      .any((s) => normalizeFolderName(s) == normalizeFolderName(_materialDocenteFolder));

  return DriveLocationResult.ok(
    DriveFileLocation(
      careerId: carrera.id,
      careerName: carrera.name,
      subject: asignatura,
      category: esGuia ? StudyFileCategory.guia : StudyFileCategory.trabajo,
    ),
  );
}
