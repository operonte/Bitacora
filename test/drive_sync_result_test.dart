import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/services/study_file_service.dart';

void main() {
  group('DriveSyncResult.resumen', () {
    test('distingue "no se pudo consultar" de "no hay nada nuevo"', () {
      // El motivo de que esta clase exista: el botón anterior decía "todo al
      // día" cuando en realidad no había podido comprobar nada, y esa mentira
      // era peor que no tener botón.
      expect(const DriveSyncResult.fallo().resumen,
          'No se pudo consultar Google Drive');
      expect(const DriveSyncResult.vacio().resumen,
          'Todo al día con Google Drive');
    });

    test('un fallo no se cuenta como "sin cambios"', () {
      expect(const DriveSyncResult.fallo().fallo, isTrue);
      expect(const DriveSyncResult.fallo().sinCambios, isFalse);
      expect(const DriveSyncResult.vacio().sinCambios, isTrue);
    });

    test('"falta autorizar" no es ni fallo ni todo al día', () {
      // La sincronización automática termina así cuando haría falta abrir la
      // ventana de permisos de Google. No es un error —no hay nada roto— pero
      // tampoco se comprobó nada, así que no puede decir "todo al día".
      const r = DriveSyncResult.faltaPermiso();
      expect(r.faltaPermiso, isTrue);
      expect(r.fallo, isFalse);
      expect(r.sinCambios, isFalse);
      expect(r.resumen, 'Falta autorizar el acceso a Google Drive');
    });

    test('sin carpeta Bitácora tampoco es todo al día', () {
      const r = DriveSyncResult.sinCarpeta();
      expect(r.sinCarpeta, isTrue);
      expect(r.resumen,
          'No se encontró la carpeta "Bitácora" en tu Google Drive');
    });

    test('cuenta lo que hizo, en singular y en plural', () {
      const uno = DriveSyncResult(
          agregados: 1, eliminados: 1, actualizados: 1, ignorados: 0);
      expect(uno.resumen,
          'Drive: 1 archivo nuevo, 1 eliminado, 1 actualizado');

      const varios = DriveSyncResult(
          agregados: 3, eliminados: 2, actualizados: 0, ignorados: 0);
      expect(varios.resumen, 'Drive: 3 archivos nuevos, 2 eliminados');
    });

    test('avisa de los archivos que quedaron sin registrar', () {
      // Que desaparezcan en silencio es lo que hace que alguien crea que la
      // app le perdió un archivo.
      const r = DriveSyncResult(
          agregados: 0, eliminados: 0, actualizados: 0, ignorados: 2);
      expect(
        r.resumen,
        'Todo al día con Google Drive. 2 archivos están en carpetas sin '
        'carrera o asignatura',
      );
    });

    test('el aviso convive con los cambios aplicados', () {
      const r = DriveSyncResult(
          agregados: 1, eliminados: 0, actualizados: 0, ignorados: 1);
      expect(
        r.resumen,
        'Drive: 1 archivo nuevo. 1 archivo está en una carpeta sin carrera '
        'o asignatura',
      );
    });
  });

  group('reconciliación de la pasada completa', () {
    // El barrido completo cuadra los dos lados: registra lo que Drive tiene y
    // la app no, y quita lo que la app tiene y Drive ya no.
    //
    // El segundo sentido es el que faltaba y dejó un archivo fantasma: la
    // Changes API solo informa de lo que pasa **desde** que se pide el token,
    // así que un archivo borrado antes de esa primera pasada no aparece en
    // ningún delta, nunca. Sin esta resta, su tarjeta se queda para siempre.
    Set<String> aBorrar(Set<String> registrados, Set<String> enDrive) =>
        registrados.difference(enDrive);

    test('quita lo registrado que Drive ya no lista', () {
      expect(aBorrar({'a', 'fantasma'}, {'a'}), {'fantasma'});
    });

    test('no toca lo que sigue en Drive', () {
      expect(aBorrar({'a', 'b'}, {'a', 'b', 'nuevo'}), isEmpty);
    });

    test('con Drive vacío se van todos los registrados', () {
      expect(aBorrar({'a', 'b'}, {}), {'a', 'b'});
    });

    test('sin nada registrado no hay nada que borrar', () {
      expect(aBorrar({}, {'a'}), isEmpty);
    });
  });
}
