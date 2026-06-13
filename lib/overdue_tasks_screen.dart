import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/task_progress_service.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'task_card.dart';
import 'colors.dart';
import 'utils/error_handler.dart';
import 'services/career_service.dart';

class OverdueTasksScreen extends StatefulWidget {
  const OverdueTasksScreen({super.key});

  @override
  _OverdueTasksScreenState createState() => _OverdueTasksScreenState();
}

class _OverdueTasksScreenState extends State<OverdueTasksScreen>
    with RouteAware {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final FirebaseService _firebaseService = FirebaseService();

  // RouteObserver para detectar cuando se regresa a esta pantalla
  static final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Obtener carrera seleccionada
    final careerService = CareerService();
    final selectedCareer = careerService.getSelectedCareer();

    // Cargar primero desde caché local para respuesta inmediata (offline-first)
    final cachedTasks = _firebaseService.getTasksFromCache();
    if (cachedTasks.isNotEmpty) {
      final overdueCached = _firebaseService
          .applyCurrentUserProgress(cachedTasks)
          .where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isPast = task.dueDate.isBefore(DateTime.now());
        // Filtrar por carrera si hay una seleccionada
        final matchesCareer =
            selectedCareer == null ||
            task.careerId == null ||
            task.careerId!.isEmpty ||
            task.careerId == selectedCareer.id;
        return !isDelivered && isPast && matchesCareer;
      }).toList()
        ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
      setState(() {
        _tasks = overdueCached;
        _isLoading = false;
      });
    }

    try {
      // Cargar todas las tareas sin filtrar por careerId inicialmente
      final allTasks = await _firebaseService.getTasks();
      // Filtrar tareas vencidas y por carrera si está seleccionada
      final overdueTasks = _firebaseService
          .applyCurrentUserProgress(allTasks)
          .where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isPast = task.dueDate.isBefore(DateTime.now());
        // Filtrar por carrera: mostrar si no tiene careerId o si coincide con la seleccionada
        final matchesCareer =
            selectedCareer == null ||
            task.careerId == null ||
            task.careerId!.isEmpty ||
            task.careerId == selectedCareer.id;
        return !isDelivered && isPast && matchesCareer;
      }).toList()
        ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

      setState(() {
        _tasks = overdueTasks;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ErrorHandler.showErrorSnackBar(
        context,
        ErrorMessages.fromFirebaseError(e),
      );
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
                color: Colors.white.withValues(alpha: 0.2),
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
            icon: const Icon(Icons.info),
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
                        color: AppColors.rojo.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.rojo.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: AppColors.rojo),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tienes ${_tasks.length} tarea(s) vencida(s). Algunas pueden requerir acción urgente.',
                              style: const TextStyle(
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
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
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
                      Icon(
                        _getUrgencyIcon(urgency),
                        color: urgencyColor,
                        size: 20,
                      ),
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
                const SizedBox(height: 16),
                const Text(
                  'Estado:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Realizada'),
                  value: task.isCompleted,
                  onChanged: (value) async {
                    if (value != null) {
                      setDialogState(() {
                        task.isCompleted = value;
                      });
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      await TaskProgressService().setProgress(
                        uid,
                        task.id!,
                        isCompleted: task.isCompleted,
                        isSubmitted: task.isSubmitted,
                      );
                      // Si marca ambos, la tarea se mueve a Entregadas
                      if (task.isCompleted && task.isSubmitted) {
                        Navigator.pop(context);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Tarea movida a Entregadas'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  activeColor: Colors.green,
                ),
                CheckboxListTile(
                  title: const Text('Enviada'),
                  value: task.isSubmitted,
                  onChanged: (value) async {
                    if (value != null) {
                      setDialogState(() {
                        task.isSubmitted = value;
                      });
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      await TaskProgressService().setProgress(
                        uid,
                        task.id!,
                        isCompleted: task.isCompleted,
                        isSubmitted: task.isSubmitted,
                      );
                      // Si marca ambos, la tarea se mueve a Entregadas
                      if (task.isCompleted && task.isSubmitted) {
                        Navigator.pop(context);
                        _loadData();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Tarea movida a Entregadas'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  activeColor: Colors.green,
                ),
                if (task.isCompleted && !task.isSubmitted)
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
                          'Realizada pero no enviada',
                          style: TextStyle(color: Colors.orange),
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
                await _firebaseService.deleteTask(task.id!, careerId: task.careerId);
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
        title: const Row(
          children: [Icon(Icons.school), SizedBox(width: 8), Text('Bitácora')],
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
                if (mounted) {
                  final appException = ErrorMessages.fromFirebaseError(e);
                  ErrorHandler.showErrorSnackBar(context, appException);
                }
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
                  await _firebaseService.deleteTask(task.id!, careerId: task.careerId);
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
