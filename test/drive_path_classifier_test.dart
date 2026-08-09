import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/models/career_model.dart';
import 'package:bitacora/models/study_file_model.dart';
import 'package:bitacora/models/subject_model.dart';
import 'package:bitacora/utils/drive_path_classifier.dart';

Subject _materia(String nombre) => Subject(
      name: nombre,
      professor: 'X',
      userId: 'u1',
      userName: 'U',
      createdAt: DateTime(2026, 1, 1),
    );

final _teologia = Career(
  id: 'teologia',
  name: 'Teología',
  accessKey: 'k1',
  predefinedSubjects: [_materia('Hebreo II'), _materia('Griego II')],
);

final _informatica = Career(
  id: 'informatica',
  name: 'Informática',
  accessKey: 'k2',
  predefinedSubjects: [_materia('Álgebra')],
);

final _carreras = [_teologia, _informatica];

void main() {
  group('classifyDrivePath', () {
    test('deduce carrera, asignatura y trabajo de Bitácora/<carrera>/<materia>',
        () {
      final r = classifyDrivePath(['Teología', 'Hebreo II'], _carreras);

      expect(r.isOk, isTrue);
      expect(r.location!.careerId, 'teologia');
      expect(r.location!.subject, 'Hebreo II');
      expect(r.location!.category, StudyFileCategory.trabajo);
    });

    test('la subcarpeta "Material docente" marca la categoría guia', () {
      final r = classifyDrivePath(
        ['Teología', 'Hebreo II', 'Material docente'],
        _carreras,
      );

      expect(r.location!.category, StudyFileCategory.guia);
      expect(r.location!.subject, 'Hebreo II');
    });

    test('compara sin tildes ni mayúsculas: la carpeta la escribe una persona',
        () {
      final r = classifyDrivePath(['teologia', 'hebreo ii'], _carreras);

      expect(r.isOk, isTrue);
      // Se guarda el nombre canónico, no lo que decía la carpeta: así la fila
      // queda igual que las que crea la app y el trigger de la base la acepta.
      expect(r.location!.subject, 'Hebreo II');
    });

    test('una subcarpeta propia del usuario no deja el archivo fuera', () {
      final r = classifyDrivePath(
        ['Teología', 'Griego II', 'Parciales', 'Segundo semestre'],
        _carreras,
      );

      expect(r.isOk, isTrue);
      expect(r.location!.subject, 'Griego II');
      expect(r.location!.category, StudyFileCategory.trabajo);
    });

    test('rechaza un archivo suelto en la raíz de Bitácora', () {
      final r = classifyDrivePath([], _carreras);

      expect(r.isOk, isFalse);
      expect(r.problem, DriveLocationProblem.sinCarrera);
    });

    test('rechaza el esquema plano viejo Bitácora/<asignatura>', () {
      // Sin carpeta de carrera no hay de dónde deducirla, aunque el nombre sí
      // sea una asignatura conocida.
      final r = classifyDrivePath(['Hebreo II'], _carreras);

      expect(r.problem, DriveLocationProblem.sinCarrera);
    });

    test('rechaza una carpeta que no es ninguna carrera del usuario', () {
      final r = classifyDrivePath(['Cocina', 'Hebreo II'], _carreras);

      expect(r.problem, DriveLocationProblem.carreraDesconocida);
    });

    test('rechaza una asignatura que no pertenece a esa carrera', () {
      // "Álgebra" existe, pero en Informática. La base lo rechazaría igual
      // (migración 16), así que adivinar solo cambiaría el aviso por un error.
      final r = classifyDrivePath(['Teología', 'Álgebra'], _carreras);

      expect(r.problem, DriveLocationProblem.asignaturaDesconocida);
    });

    test('sin carreras cargadas no inventa ninguna', () {
      final r = classifyDrivePath(['Teología', 'Hebreo II'], []);

      expect(r.problem, DriveLocationProblem.carreraDesconocida);
    });
  });
}
