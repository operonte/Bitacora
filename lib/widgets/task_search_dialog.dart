import 'package:flutter/material.dart';
import '../models/task_model.dart';

/// Diálogo de búsqueda de tareas, compartido por Pendientes, Vencidas y
/// Entregadas.
///
/// Es un StatefulWidget con su propio controlador, y no un `TextField` suelto
/// dentro de un `showDialog`, porque así estaba antes en dos pantallas: el
/// `TextEditingController` se construía dentro del `builder`, o sea que se
/// recreaba en cada reconstrucción, nunca se liberaba y perdía la posición del
/// cursor.
///
/// Devuelve la consulta al cerrarse, en vez de ir filtrando en vivo detrás del
/// modal — donde el usuario no puede ver el resultado igual.
class TaskSearchDialog extends StatefulWidget {
  final String initialQuery;

  const TaskSearchDialog({super.key, this.initialQuery = ''});

  /// Abre el diálogo. Devuelve la consulta final, o null si se canceló sin
  /// cambiar nada.
  static Future<String?> show(BuildContext context, String initialQuery) {
    return showDialog<String>(
      context: context,
      builder: (_) => TaskSearchDialog(initialQuery: initialQuery),
    );
  }

  /// Si [task] calza con [query]. Único criterio de búsqueda de la app: título,
  /// descripción, asignatura y profesor.
  static bool matches(Task task, String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();
    return task.title.toLowerCase().contains(q) ||
        task.description.toLowerCase().contains(q) ||
        task.subject.toLowerCase().contains(q) ||
        task.professor.toLowerCase().contains(q);
  }

  @override
  State<TaskSearchDialog> createState() => _TaskSearchDialogState();
}

class _TaskSearchDialogState extends State<TaskSearchDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Buscar tareas'),
      content: TextField(
        autofocus: true,
        controller: _controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Título, asignatura o profesor',
          border: const OutlineInputBorder(),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Limpiar',
                  onPressed: () => setState(_controller.clear),
                ),
        ),
        // Solo para que aparezca o desaparezca el botón de limpiar: el filtro
        // se aplica al cerrar.
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Buscar'),
        ),
      ],
    );
  }
}
