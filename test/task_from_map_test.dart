import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/models/task_model.dart';

/// `Task.fromMap` es ahora el único lector: recibe tanto el mapa de la caché
/// de Hive (`camelCase`, fechas en milisegundos) como una fila de Supabase
/// (`snake_case`, `updated_at` en ISO). Si estas pruebas fallan, o se rompe la
/// caché local de todos los dispositivos o se rompe la lectura del servidor.
void main() {
  final vence = DateTime(2026, 9, 1, 23, 59);
  final creada = DateTime(2026, 8, 1, 10, 0);

  group('Formato de la caché (camelCase)', () {
    test('lee una tarea completa', () {
      final task = Task.fromMap({
        'id': 't1',
        'title': 'Ensayo',
        'description': 'Sobre Hermenéutica',
        'subject': 'Hermenéutica bíblica',
        'professor': 'Lic. Carlos Camaño',
        'dueDate': vence.millisecondsSinceEpoch,
        'isCompleted': true,
        'isSubmitted': false,
        'type': 'trabajo',
        'createdAt': creada.millisecondsSinceEpoch,
        'userId': 'u1',
        'userName': 'Cristian',
        'careerId': 'teologia',
        'isShared': true,
        'collaborators': ['u2'],
        'updatedByName': 'Ana',
        'updatedAt': creada.millisecondsSinceEpoch,
      });

      expect(task.id, 't1');
      expect(task.title, 'Ensayo');
      expect(task.dueDate, vence);
      expect(task.isCompleted, isTrue);
      expect(task.isSubmitted, isFalse);
      expect(task.careerId, 'teologia');
      expect(task.isShared, isTrue);
      expect(task.collaborators, ['u2']);
      expect(task.updatedByName, 'Ana');
      expect(task.updatedAt, creada);
    });
  });

  group('Formato de Supabase (snake_case)', () {
    Map<String, dynamic> fila({Map<String, dynamic> extra = const {}}) => {
          'id': 't2',
          'title': 'Prueba de Griego',
          'description': 'Vocabulario',
          'subject': 'Griego',
          'professor': 'Dr. Daniel Godoy',
          'due_date': vence.millisecondsSinceEpoch,
          'is_completed': false,
          'is_submitted': false,
          'type': 'prueba',
          'created_at': creada.millisecondsSinceEpoch,
          'user_id': 'u1',
          'user_name': 'Cristian',
          'career_id': 'teologia',
          ...extra,
        };

    test('lee una fila completa', () {
      final task = Task.fromMap(fila());

      expect(task.id, 't2');
      expect(task.subject, 'Griego');
      expect(task.professor, 'Dr. Daniel Godoy');
      expect(task.dueDate, vence);
      expect(task.createdAt, creada);
      expect(task.userId, 'u1');
      expect(task.careerId, 'teologia');
    });

    test('updated_at llega como texto ISO y se parsea', () {
      final task = Task.fromMap(fila(extra: {
        'updated_at': '2026-08-05T14:30:00.000Z',
        'updated_by_name': 'Ana',
      }));

      expect(task.updatedAt, DateTime.parse('2026-08-05T14:30:00.000Z'));
      expect(task.updatedByName, 'Ana');
    });

    test('un updated_by_name vacío se guarda como null', () {
      final task = Task.fromMap(fila(extra: {'updated_by_name': '   '}));
      expect(task.updatedByName, isNull);
    });

    test('isShared lo impone la tabla de origen, no la fila', () {
      // Las filas de shared_tasks no traen columna is_shared: lo sabe quien
      // consultó la tabla.
      expect(Task.fromMap(fila(), null, true).isShared, isTrue);
      expect(Task.fromMap(fila()).isShared, isFalse);
    });
  });

  group('Campos ausentes o inválidos', () {
    test('un false no cae al otro nombre de campo', () {
      // El riesgo de escribir esto con `??`: `map['isCompleted'] ?? map['is_completed']`
      // funciona, pero un `false` legítimo en el primero seguiría siendo false;
      // el problema aparece al revés, con claves presentes y valor falsy.
      final task = Task.fromMap({
        'title': 'x',
        'description': 'y',
        'subject': 's',
        'professor': 'p',
        'dueDate': vence.millisecondsSinceEpoch,
        'createdAt': creada.millisecondsSinceEpoch,
        'userId': 'u',
        'userName': 'n',
        'isCompleted': false,
        'is_completed': true,
      });
      expect(task.isCompleted, isFalse);
    });

    test('rellena los textos vacíos con valores legibles', () {
      final task = Task.fromMap({
        'due_date': vence.millisecondsSinceEpoch,
        'created_at': creada.millisecondsSinceEpoch,
      });

      expect(task.title, 'Tarea sin título');
      expect(task.subject, 'Sin asignatura');
      expect(task.userId, 'unknown');
      expect(task.collaborators, isEmpty);
      expect(task.updatedAt, isNull);
    });

    test('rechaza una fecha que no sea número', () {
      expect(
        () => Task.fromMap({
          'title': 'x',
          'due_date': '2026-09-01',
          'created_at': creada.millisecondsSinceEpoch,
        }),
        throwsArgumentError,
      );
    });
  });
}
