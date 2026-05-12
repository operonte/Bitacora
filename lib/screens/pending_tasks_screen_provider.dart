import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../task_model.dart';
import '../task_card.dart';
import '../add_task_screen.dart';
import '../colors.dart';
import '../utils/error_handler.dart';
import '../providers/app_state.dart';

class PendingTasksScreenProvider extends StatefulWidget {
  const PendingTasksScreenProvider({Key? key}) : super(key: key);

  @override
  _PendingTasksScreenProviderState createState() => _PendingTasksScreenProviderState();
}

class _PendingTasksScreenProviderState extends State<PendingTasksScreenProvider> {
  String _selectedSubject = 'Todos';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        final tasks = appState.getTasksBySubject(_selectedSubject);
        final filteredTasks = _searchQuery.isEmpty 
            ? tasks 
            : tasks.where((task) => 
                task.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                task.description.toLowerCase().contains(_searchQuery.toLowerCase())
              ).toList();

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
              if (appState.hasPendingChanges)
                IconButton(
                  icon: const Icon(Icons.cloud_off, color: Colors.orange),
                  onPressed: () => appState.forceSync(),
                  tooltip: 'Sincronizar cambios',
                ),
            ],
          ),
          body: appState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : filteredTasks.isEmpty
                  ? const Center(
                      child: Text(
                        'No hay tareas pendientes',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => appState.loadTasks(),
                      child: ListView.builder(
                        itemCount: filteredTasks.length,
                        itemBuilder: (context, index) {
                          final task = filteredTasks[index];
                          return TaskCard(
                            task: task,
                            onTap: () => _showTaskDetails(task),
                            onEdit: () => _editTask(task),
                            onDelete: () => _deleteTask(task),
                          );
                        },
                      ),
                    ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddTaskScreen()),
            ),
            backgroundColor: AppColors.primary,
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: _buildSubjectFilter(appState),
        );
      },
    );
  }

  Widget _buildSubjectFilter(AppState appState) {
    final subjects = appState.uniqueSubjects;
    
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: subjects.length,
        itemBuilder: (context, index) {
          final subject = subjects[index];
          final isSelected = subject == _selectedSubject;
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(subject),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedSubject = subject;
                });
              },
              backgroundColor: isSelected ? AppColors.primary : Colors.grey[200],
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
              ),
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
        title: const Text('Buscar Tarea'),
        content: TextField(
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
            Navigator.pop(context);
          },
          decoration: const InputDecoration(
            hintText: 'Buscar por título, descripción o materia...',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ),
    );
  }

  void _showTaskDetails(Task task) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Materia: ${task.subject}'),
              Text('Profesor: ${task.professor}'),
              Text('Tipo: ${task.type}'),
              Text('Fecha: ${task.dueDate.toString().split(' ')[0]}'),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Descripción: ${task.description}'),
              ],
              if (task.tag != null) ...[
                const SizedBox(height: 8),
                Chip(label: Text(task.tag!)),
              ],
            ],
          ),
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
              final appState = context.read<AppState>();
              await appState.deleteTask(task.id!);
              
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
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
