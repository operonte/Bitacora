import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'task_card.dart';
import 'colors.dart';
import 'app_icon_widget.dart';

class OverdueTasksScreen extends StatefulWidget {
  const OverdueTasksScreen({Key? key}) : super(key: key);

  @override
  _OverdueTasksScreenState createState() => _OverdueTasksScreenState();
}

class _OverdueTasksScreenState extends State<OverdueTasksScreen> {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final tasks = await _firebaseService.getOverdueTasks();

      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al cargar tareas: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Tareas Vencidas'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_tasks.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const AppIconWidget(size: 24),
            onPressed: () => _showAppInfo(),
            tooltip: 'Acerca de',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_completed') {
                _markAllAsCompleted();
              } else if (value == 'delete_completed') {
                _deleteCompletedTasks();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_completed',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Marcar todas como completadas'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete_completed',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Eliminar completadas'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(
              child: Text(
                'No hay tareas vencidas',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Column(
                children: [
                  if (_tasks.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.rojo.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.rojo.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: AppColors.rojo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tienes ${_tasks.length} tarea(s) vencida(s). Algunas pueden requerir acción urgente.',
                              style: TextStyle(
                                color: AppColors.rojo,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tasks.length,
                      itemBuilder: (context, index) {
                        final task = _tasks[index];
                        return TaskCard(
                          task: task,
                          onTap: () => _showTaskDetails(task),
                          onEdit: () => _editTask(task),
                          onDelete: () => _deleteTask(task),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showTaskDetails(Task task) {
    final urgency = task.getUrgency();
    final urgencyText = TaskColorHelper.getUrgencyText(urgency);
    final urgencyColor = TaskColorHelper.getUrgencyColor(urgency);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: urgencyColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getUrgencyIcon(urgency), color: urgencyColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    urgencyText,
                    style: TextStyle(
                      color: urgencyColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Asignatura: ${task.subject}'),
            Text('Profesor: ${task.professor}'),
            Text('Tipo: ${task.type}'),
            Text(
              'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(task.dueDate)}',
            ),
            const SizedBox(height: 8),
            Text('Descripción: ${task.description}'),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  task.isCompleted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: task.isCompleted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(task.isCompleted ? 'Realizada' : 'No realizada'),
              ],
            ),
            Row(
              children: [
                Icon(
                  task.isSubmitted
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: task.isSubmitted ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(task.isSubmitted ? 'Enviada' : 'No enviada'),
              ],
            ),
            if (task.needsSubmittedMarker())
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Falta marcar como enviada',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ],
                ),
              ),
          ],
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

  IconData _getUrgencyIcon(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.completed:
        return Icons.check_circle;
      case TaskUrgency.overdue:
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  void _editTask(Task task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Tarea'),
        content: const Text(
          'Para editar tareas vencidas, ve a la pantalla de tareas pendientes.',
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

  void _deleteTask(Task task) {
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
                await _firebaseService.deleteTask(task.id!);
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al eliminar: $e')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showAppInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const AppIconWidget(size: 32),
            const SizedBox(width: 8),
            const Text('Bitácora'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versión: 1.0.0'),
            SizedBox(height: 8),
            Text('Una aplicación para gestionar tus tareas académicas.'),
            SizedBox(height: 8),
            Text(
              'Icono representa un libro con casillas de verificación, simbolizando el seguimiento de actividades académicas.',
            ),
          ],
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

  void _markAllAsCompleted() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Marcar todas como completadas'),
        content: const Text(
          '¿Estás seguro de marcar todas las tareas vencidas como completadas?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                for (final task in _tasks) {
                  if (!task.isCompleted) {
                    task.isCompleted = true;
                    await _firebaseService.updateTask(task);
                  }
                }
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Todas las tareas marcadas como completadas'),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al actualizar: $e')),
                );
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _deleteCompletedTasks() {
    final completedTasks = _tasks.where((task) => task.isCompleted).toList();

    if (completedTasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay tareas completadas para eliminar'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar tareas completadas'),
        content: Text(
          '¿Estás seguro de eliminar ${completedTasks.length} tarea(s) completada(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                for (final task in completedTasks) {
                  await _firebaseService.deleteTask(task.id!);
                }
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${completedTasks.length} tarea(s) eliminada(s)',
                    ),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al eliminar: $e')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
