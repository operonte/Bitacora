import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../widgets/staggered_entrance.dart';
import 'add_task_screen.dart';
import '../utils/error_handler.dart';
import '../services/career_service.dart';
import '../services/sync_service.dart';
import '../colors.dart';
import 'config_screen.dart';

class DeliveredTasksScreen extends StatefulWidget {
  const DeliveredTasksScreen({super.key});

  @override
  State<DeliveredTasksScreen> createState() => _DeliveredTasksScreenState();
}

class _DeliveredTasksScreenState extends State<DeliveredTasksScreen> {
  String _searchQuery = '';

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar en Entregadas'),
        content: TextField(
          autofocus: true,
          controller: TextEditingController(text: _searchQuery),
          decoration: InputDecoration(
            hintText: 'Buscar por título, materia...',
            border: const OutlineInputBorder(),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() => _searchQuery = '');
                      Navigator.pop(context);
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
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

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';

    final appState = context.watch<AppState>();
    final allDeliveredTasks = appState.deliveredTasks;

    final deliveredTasks = allDeliveredTasks.where((task) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return task.title.toLowerCase().contains(q) ||
          task.description.toLowerCase().contains(q) ||
          task.subject.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tareas Entregadas'),
                if (deliveredTasks.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${deliveredTasks.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (careerName.isNotEmpty)
              Text(
                careerName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: context.textSecondaryColor,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.search,
              color: _searchQuery.isNotEmpty
                  ? (context.isDark ? AppColors.primaryLight : AppColors.primary)
                  : null,
            ),
            onPressed: _showSearchDialog,
            tooltip: 'Buscar',
          ),
          SyncIndicator(syncService: SyncService()),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfigScreen()),
            ),
            tooltip: 'Configuración',
          ),
        ],
      ),
      body: appState.isLoading && deliveredTasks.isEmpty
          ? ListView.builder(
              itemCount: 3,
              itemBuilder: (context, index) => const SkeletonTaskCard(),
            )
          : deliveredTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: context.textSecondaryColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No hay tareas entregadas',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Las tareas aparecerán aquí cuando\nestén realizadas y enviadas',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => appState.forceSync(),
                  child: ListView.builder(
                    itemCount: deliveredTasks.length,
                    itemBuilder: (context, index) {
                      final task = deliveredTasks[index];
                      return StaggeredEntrance(
                        index: index,
                        child: TaskCard(
                          task: task,
                          onTap: () => _showTaskDetails(task, appState),
                          onEdit: () => _editTask(task),
                          onDelete: () => _deleteTask(task, appState),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showTaskDetails(Task task, AppState appState) {
    var localCompleted = task.isCompleted;
    var localSubmitted = task.isSubmitted;

    Future<void> updateStatus(bool completed, bool submitted, void Function(void Function()) setDialogState) async {
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
      // Si desmarca alguno, la tarea ya no es "entregada"
      if (!localCompleted || !localSubmitted) {
        Navigator.pop(context);
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
                if (localCompleted && localSubmitted)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green),
                        SizedBox(width: 8),
                        Text(
                          'Tarea completamente entregada',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
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

  void _editTask(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(task: task)),
    );
  }

  void _deleteTask(Task task, AppState appState) {
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
                  final appException = ErrorMessages.fromFirebaseError(e);
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
