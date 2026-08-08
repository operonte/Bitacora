import 'package:flutter_test/flutter_test.dart';
import 'package:bitacora/models/task_model.dart';
import 'package:bitacora/widgets/task_search_dialog.dart';

Task _task({
  String title = 'Ensayo de Hermenéutica',
  String description = 'Sobre el contexto del texto',
  String subject = 'Hermenéutica bíblica',
  String professor = 'Lic. Carlos Camaño',
}) {
  return Task(
    title: title,
    description: description,
    subject: subject,
    professor: professor,
    dueDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 8, 1),
    userId: 'u1',
    userName: 'Usuario',
  );
}

void main() {
  group('Filtro de búsqueda de tareas', () {
    test('una consulta vacía deja pasar todo', () {
      expect(TaskSearchDialog.matches(_task(), ''), isTrue);
      expect(TaskSearchDialog.matches(_task(), '   '), isTrue);
    });

    test('busca en título, descripción, asignatura y profesor', () {
      final task = _task();
      expect(TaskSearchDialog.matches(task, 'ensayo'), isTrue);
      expect(TaskSearchDialog.matches(task, 'contexto'), isTrue);
      expect(TaskSearchDialog.matches(task, 'bíblica'), isTrue);
      expect(TaskSearchDialog.matches(task, 'camaño'), isTrue);
    });

    test('ignora mayúsculas y espacios de sobra', () {
      expect(TaskSearchDialog.matches(_task(), '  ENSAYO '), isTrue);
    });

    test('no devuelve lo que no calza', () {
      expect(TaskSearchDialog.matches(_task(), 'álgebra'), isFalse);
    });
  });
}
