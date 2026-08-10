import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../utils/error_handler.dart';

/// Diálogo de detalle de una tarea, con checkboxes de estado.
///
/// Estaba copiado tres veces entre pending/overdue/delivered_tasks_screen,
/// idéntico salvo en cuándo avisa el cambio de estado: pending y overdue
/// avisan al *entrar* a Entregadas (las dos casillas quedan en true);
/// delivered avisa al *salir* (alguna vuelve a false). Eso es lo único que
/// varía con [isDeliveredView].
class TaskDetailsDialog {
  static void show(
    BuildContext context, {
    required Task task,
    required AppState appState,
    required bool isDeliveredView,
  }) {
    var localCompleted = task.isCompleted;
    var localSubmitted = task.isSubmitted;

    Future<void> updateStatus(
      bool completed,
      bool submitted,
      void Function(void Function()) setDialogState,
    ) async {
      final success = await appState.updateTaskStatus(task.id!, completed, submitted);
      if (!context.mounted) return;
      if (!success) {
        ErrorHandler.showErrorSnackBar(
          context,
          AppException(type: AppErrorType.unknown, message: appState.error),
        );
        return;
      }
      setDialogState(() {
        localCompleted = completed;
        localSubmitted = submitted;
      });

      final entregada = completed && submitted;
      final saleDeEntregada = !completed || !submitted;
      if (isDeliveredView ? saleDeEntregada : entregada) {
        Navigator.pop(context);
        if (!isDeliveredView) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Tarea movida a Entregadas'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.title),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asignatura: ${task.subject}'),
                Text('Profesor: ${task.professor}'),
                Text('Creado por: ${task.userName}'),
                Text('Tipo: ${task.type}'),
                Text(
                  'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(task.dueDate)}',
                ),
                const SizedBox(height: 8),
                Text('Descripción: ${task.description}'),
                const SizedBox(height: 16),
                const Text(
                  'Estado:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Realizada'),
                  value: localCompleted,
                  onChanged: (value) async {
                    if (value != null) {
                      await updateStatus(value, localSubmitted, setDialogState);
                    }
                  },
                  activeColor: Colors.green,
                ),
                CheckboxListTile(
                  title: const Text('Enviada'),
                  value: localSubmitted,
                  onChanged: (value) async {
                    if (value != null) {
                      await updateStatus(localCompleted, value, setDialogState);
                    }
                  },
                  activeColor: Colors.green,
                ),
                if (isDeliveredView)
                  if (localCompleted && localSubmitted)
                    _banner(
                      Icons.check_circle,
                      Colors.green,
                      'Tarea completamente entregada',
                    )
                  else
                    const SizedBox.shrink()
                else if (localCompleted && !localSubmitted)
                  _banner(
                    Icons.warning,
                    Colors.orange,
                    'Realizada pero no enviada',
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  static Widget _banner(IconData icon, Color color, String text) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  /// Confirma y borra una tarea. Copiado idéntico en las tres pantallas.
  static void confirmDelete(
    BuildContext context, {
    required Task task,
    required AppState appState,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Tarea'),
        content: Text('¿Estás seguro de eliminar "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final success = await appState.deleteTask(task.id!);
                if (!context.mounted) return;
                if (!success) {
                  ErrorHandler.showErrorSnackBar(
                    context,
                    AppException(type: AppErrorType.unknown, message: appState.error),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
                );
              } catch (e) {
                if (context.mounted) {
                  final appException = ErrorMessages.fromBackendError(e);
                  ErrorHandler.showErrorSnackBar(context, appException);
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
