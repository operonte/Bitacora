import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/task_progress_service.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'task_card.dart';
import 'add_task_screen.dart';
import 'colors.dart';
import 'utils/error_handler.dart';
import 'utils/logger.dart';
import 'services/career_service.dart';

class PendingTasksScreen extends StatefulWidget {
  const PendingTasksScreen({super.key});

  @override
  _PendingTasksScreenState createState() => _PendingTasksScreenState();
}

class _PendingTasksScreenState extends State<PendingTasksScreen>
    with RouteAware {
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  String _selectedSubject = 'Todos';
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

  /// Se llama cuando el usuario vuelve a esta pantalla (pop de otra ruta)
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
      final pendingCached = cachedTasks.where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isFuture = task.dueDate.isAfter(DateTime.now());
        // Filtrar por carrera si hay una seleccionada
        // Igual que el filtro de Firebase: tareas sin careerId se muestran siempre
        final matchesCareer =
            selectedCareer == null ||
            task.careerId == null ||
            task.careerId!.isEmpty ||
            task.careerId == selectedCareer.id;
        return !isDelivered && isFuture && matchesCareer;
      }).toList();
      setState(() {
        _tasks = pendingCached;
        _filteredTasks = pendingCached; // FIX: inicializar _filteredTasks
        _isLoading = false;
      });
    }

    try {
      // Cargar todas las tareas sin filtrar por careerId inicialmente
      final allTasks = await _firebaseService.getTasks();
      Logger.info(
        'Carrera seleccionada: ${selectedCareer?.name} (id: ${selectedCareer?.id})',
      );
      Logger.info('Total tareas desde Firebase: ${allTasks.length}');
      for (final task in allTasks) {
        Logger.info('Tarea: ${task.title}, careerId: ${task.careerId}');
      }
      // Filtrar tareas pendientes y por carrera si está seleccionada
      final pendingTasks = allTasks.where((task) {
        final isDelivered = task.isCompleted && task.isSubmitted;
        final isFuture = task.dueDate.isAfter(DateTime.now());
        // Filtrar por carrera: mostrar si no tiene careerId o si coincide con la seleccionada
        final matchesCareer =
            selectedCareer == null ||
            task.careerId == null ||
            task.careerId!.isEmpty ||
            task.careerId == selectedCareer.id;
        return !isDelivered && isFuture && matchesCareer;
      }).toList();
      Logger.info('Tareas después del filtro: ${pendingTasks.length}');

      setState(() {
        _tasks = pendingTasks;
        _filteredTasks =
            pendingTasks; // FIX: sincronizar _filteredTasks con datos frescos
        _selectedSubject = 'Todos'; // resetear filtro de materia
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

  void _filterTasks(String subject) {
    setState(() {
      _selectedSubject = subject;
      if (subject == 'Todos') {
        _filteredTasks = _tasks;
      } else {
        _filteredTasks = _tasks
            .where((task) => task.subject == subject)
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tareas Pendientes'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSubjectFilter(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTasks.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      itemCount: _filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = _filteredTasks[index];
                        return TaskCard(
                          task: task,
                          onTap: () => _showTaskDetails(task),
                          onEdit: () => _editTask(task),
                          onDelete: () => _deleteTask(task),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                size: 64,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '¡Todo al día!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'No tienes tareas pendientes.\nAgrega una nueva para empezar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _addTask,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Nueva tarea'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectFilter() {
    // Obtener materias únicas de las tareas
    final subjectNames = _tasks.map((task) => task.subject).toSet().toList();
    subjectNames.sort();
    subjectNames.insert(0, 'Todos');

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: subjectNames.length,
        itemBuilder: (context, index) {
          final subject = subjectNames[index];
          final isSelected = subject == _selectedSubject;

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(subject),
              selected: isSelected,
              onSelected: (_) => _filterTasks(subject),
              backgroundColor: isSelected
                  ? AppColors.primary.withValues(alpha: 0.2)
                  : Colors.grey[200],
              checkmarkColor: AppColors.primary,
            ),
          );
        },
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buscar Tareas'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Escribe para buscar...',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            setState(() {
              _filteredTasks = _tasks
                  .where(
                    (task) =>
                        task.title.toLowerCase().contains(
                          value.toLowerCase(),
                        ) ||
                        task.description.toLowerCase().contains(
                          value.toLowerCase(),
                        ) ||
                        task.subject.toLowerCase().contains(
                          value.toLowerCase(),
                        ),
                  )
                  .toList();
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
                      setDialogState(() => task.isCompleted = value);
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      await TaskProgressService().setProgress(
                        uid,
                        task.id!,
                        isCompleted: task.isCompleted,
                        isSubmitted: task.isSubmitted,
                      );
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
                      setDialogState(() => task.isSubmitted = value);
                      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                      await TaskProgressService().setProgress(
                        uid,
                        task.id!,
                        isCompleted: task.isCompleted,
                        isSubmitted: task.isSubmitted,
                      );
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
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Realizada pero no enviada',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
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

  void _addTask() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );

    if (result != null) {
      _loadData();
    }
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
                await _firebaseService.deleteTask(task.id!);
                _loadData();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
                );
              } catch (e) {
                if (mounted) {
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
