import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/models/study_file_model.dart';

void main() {
  group('StudyFileCategory', () {
    test('reconoce guia y cae en trabajo ante cualquier otra cosa', () {
      expect(StudyFileCategory.parse('guia'), StudyFileCategory.guia);
      expect(StudyFileCategory.parse('trabajo'), StudyFileCategory.trabajo);
      // Filas anteriores a la columna category llegan sin valor.
      expect(StudyFileCategory.parse(null), StudyFileCategory.trabajo);
      expect(StudyFileCategory.parse('cualquier_cosa'), StudyFileCategory.trabajo);
    });
  });

  group('StudyFile.fromMap', () {
    test('lee created_at en ISO 8601, que es lo que devuelve Supabase', () {
      final file = StudyFile.fromMap({
        'id': '1',
        'name': 'guia.pdf',
        'subject': 'Hebreo',
        'user_id': 'u1',
        'created_at': '2026-08-03T12:30:00.000Z',
      });

      expect(file.createdAt.toUtc().year, 2026);
      expect(file.createdAt.toUtc().month, 8);
      expect(file.createdAt.toUtc().day, 3);
    });

    test('lee created_at en epoch, el formato del material docente viejo', () {
      // El modelo TeachingMaterial serializaba millisecondsSinceEpoch, así
      // que la caché local de quien ya lo usó tiene números, no fechas ISO.
      final epoch = DateTime.utc(2026, 3, 1, 9).millisecondsSinceEpoch;

      final fromNumber = StudyFile.fromMap({
        'name': 'apunte.pdf',
        'user_id': 'u1',
        'created_at': epoch,
      });
      final fromString = StudyFile.fromMap({
        'name': 'apunte.pdf',
        'user_id': 'u1',
        'created_at': '$epoch',
      });

      expect(fromNumber.createdAt.toUtc().year, 2026);
      expect(fromNumber.createdAt.toUtc().month, 3);
      expect(fromString.createdAt, fromNumber.createdAt);
    });

    test('acepta title como nombre, que es como lo guardaba el modelo viejo', () {
      final file = StudyFile.fromMap({
        'title': 'Guía de Griego',
        'subject': 'Griego',
        'user_id': 'u1',
        'category': 'guia',
      });

      expect(file.name, 'Guía de Griego');
      expect(file.category, StudyFileCategory.guia);
    });

    test('deja en null los campos de Drive vacíos en vez de guardar cadenas', () {
      final link = StudyFile.fromMap({
        'name': 'Clase grabada',
        'user_id': 'u1',
        'drive_file_id': '',
        'mime_type': 'null',
        'external_url': 'https://youtu.be/abc',
      });

      expect(link.driveFileId, isNull);
      expect(link.mimeType, isNull);
      expect(link.isLink, isTrue);
      expect(link.openUrl, 'https://youtu.be/abc');
      // Sin tamaño no debe mostrar "0 B".
      expect(link.formattedSize, '');
    });

    test('un archivo de Drive abre por su enlace de Drive', () {
      final file = StudyFile(
        name: 'ensayo.pdf',
        subject: 'Hebreo',
        driveFileId: 'abc123',
        driveLink: 'https://drive.google.com/file/d/abc123',
        sizeBytes: 2048,
        userId: 'u1',
      );

      expect(file.isLink, isFalse);
      expect(file.openUrl, 'https://drive.google.com/file/d/abc123');
      expect(file.formattedSize, '2.0 KB');
      expect(file.category, StudyFileCategory.trabajo);
    });
  });

  group('StudyFile.toMap', () {
    test('ida y vuelta conserva los campos', () {
      final original = StudyFile(
        id: '42',
        name: 'guia.pdf',
        subject: 'Álgebra',
        driveFileId: 'd1',
        mimeType: 'pdf',
        sizeBytes: 100,
        driveLink: 'https://drive/d1',
        userId: 'u1',
        category: StudyFileCategory.guia,
        description: 'Capítulo 3',
        createdAt: DateTime.utc(2026, 8, 3, 10),
      );

      final restored = StudyFile.fromMap(original.toMap());

      expect(restored.id, '42');
      expect(restored.name, 'guia.pdf');
      expect(restored.subject, 'Álgebra');
      expect(restored.category, StudyFileCategory.guia);
      expect(restored.description, 'Capítulo 3');
      expect(restored.sizeBytes, 100);
      expect(restored.createdAt.toUtc(), original.createdAt.toUtc());
    });
  });
}
