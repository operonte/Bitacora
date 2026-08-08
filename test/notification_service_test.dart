import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/models/meeting_model.dart';
import 'package:bitacora/notification_service.dart';

Meeting _meeting({
  required DateTime date,
  bool isRecurrent = false,
}) {
  return Meeting(
    title: 'Reunión',
    subject: 'Griego',
    professor: 'Profesor',
    meetingDate: date,
    type: 'Zoom',
    isRecurrent: isRecurrent,
    userId: 'u1',
  );
}

void main() {
  group('Texto del resumen diario', () {
    test('cuenta reuniones y tareas juntas', () {
      expect(
        NotificationService.digestBody(tareas: 2, reuniones: 3),
        'Hoy tienes 3 reuniones y 2 tareas con fecha límite',
      );
    });

    test('usa singular cuando hay una sola', () {
      expect(
        NotificationService.digestBody(tareas: 1, reuniones: 1),
        'Hoy tienes 1 reunión y 1 tarea con fecha límite',
      );
    });

    test('omite la parte que está en cero', () {
      expect(
        NotificationService.digestBody(tareas: 0, reuniones: 2),
        'Hoy tienes 2 reuniones',
      );
      expect(
        NotificationService.digestBody(tareas: 4, reuniones: 0),
        'Hoy tienes 4 tareas con fecha límite',
      );
    });
  });

  group('Ocurrencia de una reunión en un día', () {
    test('una puntual solo cuenta el día de su fecha', () {
      final dia = DateTime(2026, 8, 10);
      final m = _meeting(date: DateTime(2026, 8, 10, 14, 30));

      expect(NotificationService.occurrenceOn(m, dia), isNotNull);
      expect(
        NotificationService.occurrenceOn(m, DateTime(2026, 8, 11)),
        isNull,
      );
    });

    test('una semanal se repite el mismo día de la semana', () {
      // 10 de agosto de 2026 es lunes.
      final m = _meeting(
        date: DateTime(2026, 8, 10, 9, 0),
        isRecurrent: true,
      );

      final semanaSiguiente =
          NotificationService.occurrenceOn(m, DateTime(2026, 8, 17));
      expect(semanaSiguiente, DateTime(2026, 8, 17, 9, 0));

      // Martes: no toca.
      expect(
        NotificationService.occurrenceOn(m, DateTime(2026, 8, 18)),
        isNull,
      );
    });

    test('una semanal no cuenta antes de que empiece la serie', () {
      final m = _meeting(
        date: DateTime(2026, 8, 10, 9, 0),
        isRecurrent: true,
      );

      // Lunes anterior al primero: la reunión todavía no existía.
      expect(
        NotificationService.occurrenceOn(m, DateTime(2026, 8, 3)),
        isNull,
      );
    });
  });
}
