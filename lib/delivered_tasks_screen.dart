import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/task_progress_service.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'task_card.dart';
import 'add_task_screen.dart';
import 'colors.dart';
import 'utils/error_handler.dart';
import 'utils/logger.dart';
import 'services/career_service.dart';

class DeliveredTasksScreen extends StatefulWidget {
  const DeliveredTasksScreen({super.key});

  @override
  _DeliveredTasksScreenState createState() => _DeliveredTasksScreenState();
}

class _DeliveredTasksScreenState extends State<DeliveredTasksScreen>
    with RouteAware {
  List<Task> _tasks = [];
  bool _isLoading = true;
  final FirebaseService _firebaseService = FirebaseService();

  StreamSubscription<void>? _changesSubscription;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRemoteChanges();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _changesSubscription?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  /// Escucha cambios remotos (tareas y progreso) para refrescar la pantalla
  /// automáticamente cuando otro dispositivo modifica datos.
  void _subscribeToRemoteChanges() {
    _changesSubscription = _firebaseService.watchRelevantChanges().listen(
      (_) {
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 500), _loadData);
      },
      onError: (e) {
        Logger.warning(
          'Error escuchando cambios remotos',
          error: e,
          tag: 'DeliveredTasks',
        );
      },
    );
  }

  @override
  void didPopNext() {
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final careerService = CareerService();

    // Cargar primero desde caché local para respuesta inmediata (offline-first)
    final cachedTasks = _firebaseService.getTasksFromCache();
    if (cachedTasks.isNotEmpty) {
      final deliveredCached = _firebaseService
          .applyCurrentUserProgress(cachedTasks)
          .where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        // Filtrar por carrera si hay una seleccionada
        final matchesCareer = careerService.matchesAnyCareer(task.careerId);
        return isDelivered && matchesCareer;
      }).toList()
        ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
      setState(() {
        _tasks = deliveredCached;
        _isLoading = false;
      });
    }

    try {
      // Cargar todas las tareas sin filtrar por careerId inicialmente
      final allTasks = await _firebaseService.getTasks();
      // Filtrar tareas entregadas y por carrera si está seleccionada
      final deliveredTasks = _firebaseService
          .applyCurrentUserProgress(allTasks)
          .where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        // Filtrar por carrera: mostrar si no tiene careerId o si coincide con la seleccionada
        final matchesCareer = careerService.matchesAnyCareer(task.careerId);
        return isDelivered && matchesCareer;
      }).toList()
        ..sort((a, b) => b.dueDate.compareTo(a.dueDate));

      setState(() {
        _tasks = deliveredTasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
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
            const Text('Tareas Entregadas'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No hay tareas entregadas',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Las tareas aparecerán aquí cuando\nestén realizadas y enviadas',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
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
    );
  }

  void _showTaskDetails(Task task) {
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
                      if (!context.mounted) return;
                      // Si desmarca alguno, la tarea ya no es "entregada"
                      if (!task.isCompleted || !task.isSubmitted) {
                        Navigator.pop(context);
                        _loadData();
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
                      if (!context.mounted) return;
                      // Si desmarca alguno, la tarea ya no es "entregada"
                      if (!task.isCompleted || !task.isSubmitted) {
                        Navigator.pop(context);
                        _loadData();
                      }
                    }
                  },
                  activeColor: Colors.green,
                ),
                if (task.isCompleted && task.isSubmitted)
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

  void _editTask(Task task) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(task: task)),
    );

    if (result != null) {
      _loadData();
    }
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

                if (!context.mounted) return;
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
