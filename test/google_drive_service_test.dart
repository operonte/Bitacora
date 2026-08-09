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

  group('BitacoraTree', () {
    // Bitácora/
    //   Teología/
    //     Hebreo II/
    //       Material docente/
    const arbol = BitacoraTree(rootId: 'raiz', paths: {
      'raiz': [],
      'carrera': ['Teología'],
      'materia': ['Teología', 'Hebreo II'],
      'guias': ['Teología', 'Hebreo II', 'Material docente'],
    });

    DriveEntry archivoEn(List<String> parents) =>
        DriveEntry(id: 'f1', name: 'apunte.pdf', parents: parents);

    test('reconoce la raíz y sus descendientes', () {
      expect(arbol.containsFolder('raiz'), isTrue);
      expect(arbol.containsFolder('guias'), isTrue);
    });

    test('deja fuera una carpeta ajena', () {
      // Es la única barrera que queda: con permiso completo de Drive, Google
      // ya no impide que la app toque un archivo de otra parte.
      expect(arbol.containsFolder('fotos_familiares'), isFalse);
      expect(arbol.containsEntry(archivoEn(['fotos_familiares'])), isFalse);
    });

    test('un archivo sin carpeta informada no cuenta como propio', () {
      // Sin saber dónde está no se puede afirmar que sea nuestro, y ante la
      // duda no se toca.
      expect(arbol.containsFolder(null), isFalse);
      expect(arbol.containsEntry(archivoEn([])), isFalse);
    });

    test('devuelve la ruta con la que se clasifica el archivo', () {
      expect(arbol.pathOf(archivoEn(['materia'])), ['Teología', 'Hebreo II']);
      expect(arbol.pathOf(archivoEn(['guias'])),
          ['Teología', 'Hebreo II', 'Material docente']);
    });

    test('no da ruta para algo de fuera del árbol', () {
      expect(arbol.pathOf(archivoEn(['fotos_familiares'])), isNull);
    });

    test('basta un padre dentro del árbol: en Drive un archivo puede tener varios',
        () {
      expect(arbol.containsEntry(archivoEn(['ajena', 'materia'])), isTrue);
    });
  });

  group('DriveChange.isGone', () {
    DriveEntry entry({bool trashed = false}) => DriveEntry(
          id: 'f1',
          name: 'apunte.pdf',
          parents: const ['materia'],
          trashed: trashed,
        );

    test('borrado definitivo', () {
      expect(
        const DriveChange(fileId: 'f1', removed: true).isGone,
        isTrue,
      );
    });

    test('en la papelera cuenta como ausente', () {
      // El usuario ya lo dio por borrado, aunque el enlace le siga
      // funcionando a él por ser el dueño.
      expect(
        DriveChange(fileId: 'f1', removed: false, file: entry(trashed: true))
            .isGone,
        isTrue,
      );
    });

    test('un archivo vivo no está ausente', () {
      expect(
        DriveChange(fileId: 'f1', removed: false, file: entry()).isGone,
        isFalse,
      );
    });

    test('sin datos del archivo se trata como ausente, no como presente', () {
      expect(
        const DriveChange(fileId: 'f1', removed: false).isGone,
        isTrue,
      );
    });
  });
}
