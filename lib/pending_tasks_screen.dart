import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'task_card.dart';
import 'add_task_screen.dart';
import 'colors.dart';
import 'utils/error_handler.dart';

class PendingTasksScreen extends StatefulWidget {
  const PendingTasksScreen({Key? key}) : super(key: key);

  @override
  _PendingTasksScreenState createState() => _PendingTasksScreenState();
}

class _PendingTasksScreenState extends State<PendingTasksScreen> {
  List<Task> _tasks = [];
  List<Task> _filteredTasks = [];
  String _selectedSubject = 'Todos';
  List<Map<String, dynamic>> _subjects = [];
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
      final tasks = await _firebaseService.getPendingTasks();
      // Materias de la carrera de Teología con sus profesores
      final subjects = [
        {'name': 'Todos', 'color': Colors.grey},
        {
          'name': 'Contexto Literario del Antiguo Testamento',
          'professor': 'Dr. Daniel Godoy',
          'color': Colors.blue,
        },
        {
          'name': 'Hermenéutica Bíblica',
          'professor': 'Lic. Carlos Caamaño Espinoza',
          'color': Colors.green,
        },
        {
          'name': 'Metodología del Estudio Bíblico',
          'professor': 'Lic. Carlos Caamaño Espinoza',
          'color': Colors.orange,
        },
        {
          'name': 'Historia de la Iglesia I',
          'professor': 'Mg. Cecilia Castillo N.',
          'color': Colors.purple,
        },
        {
          'name': 'Historia de Israel I',
          'professor': 'Mg. Jaime Alarcón',
          'color': Colors.red,
        },
        {
          'name': 'Comunicaciones y Redacción',
          'professor': 'Dr. Patricio Abarca Castro',
          'color': Colors.teal,
        },
        {
          'name': 'Hebreo Bíblico I',
          'professor': 'Lic. Hemir Ochoa',
          'color': Colors.indigo,
        },
      ];

      setState(() {
        _tasks = tasks;
        _filteredTasks = tasks;
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final appException = ErrorMessages.fromFirebaseError(e);
        ErrorHandler.showErrorSnackBar(context, appException);
      }
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
                ? const Center(
                    child: Text(
                      'No hay tareas pendientes',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  )
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

  Widget _buildSubjectFilter() {
    // _subjects ya incluye 'Todos' al inicio, no necesitamos agregarlo de nuevo
    final subjectNames = _subjects.map((s) => s['name'] as String).toList();

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
                      setDialogState(() {
                        task.isCompleted = value;
                      });
                      await _firebaseService.updateTaskStatus(
                        task.id!,
                        task.isCompleted,
                        task.isSubmitted,
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
                      await _firebaseService.updateTaskStatus(
                        task.id!,
                        task.isCompleted,
                        task.isSubmitted,
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
                      color: Colors.orange.withOpacity(0.1),
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
