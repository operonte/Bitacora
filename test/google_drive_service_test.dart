import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/services/google_drive_service.dart';

void main() {
  group('normalizeFolderName', () {
    test('quita tildes y mayúsculas', () {
      expect(normalizeFolderName('Teología'), 'teologia');
      expect(normalizeFolderName('Informática'), 'informatica');
      expect(normalizeFolderName('Hermenéutica bíblica'), 'hermeneutica biblica');
    });

    test('hace calzar la carpeta escrita a mano con el nombre de la carrera', () {
      // El caso real que motivó esto: la carpeta de Drive la escribió una
      // persona sin tildes y la carrera viene de la base con ellas. Sin
      // normalizar, la app creaba una carpeta duplicada al lado.
      expect(
        normalizeFolderName('Teologia'),
        normalizeFolderName('Teología'),
      );
      expect(
        normalizeFolderName('  INFORMATICA  '),
        normalizeFolderName('Informática'),
      );
    });

    test('cubre la eñe y la cedilla', () {
      expect(normalizeFolderName('Diseño'), 'diseno');
      expect(normalizeFolderName('Françês'), 'frances');
    });

    test('deja intacto lo que ya está normalizado', () {
      expect(normalizeFolderName('griego'), 'griego');
      expect(normalizeFolderName('Material docente'), 'material docente');
    });

    test('no confunde dos carreras distintas', () {
      expect(
        normalizeFolderName('Teología') == normalizeFolderName('Informática'),
        isFalse,
      );
    });
  });
}
