import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../app_info.dart';
import '../providers/app_state.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/task_search_dialog.dart';
import '../widgets/task_details_dialog.dart';
import 'add_task_screen.dart';
import '../colors.dart';
import '../utils/error_handler.dart';
import '../services/career_service.dart';
import '../services/sync_service.dart';
import 'config_screen.dart';

class OverdueTasksScreen extends StatefulWidget {
  const OverdueTasksScreen({super.key});

  @override
  State<OverdueTasksScreen> createState() => _OverdueTasksScreenState();
}

class _OverdueTasksScreenState extends State<OverdueTasksScreen> {
  String _searchQuery = '';

  Future<void> _showSearchDialog() async {
    final query = await TaskSearchDialog.show(context, _searchQuery);
    if (query == null || !mounted) return;
    setState(() => _searchQuery = query);
  }

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';

    final appState = context.watch<AppState>();
    // Vencidas es justo donde se acumulan las tareas de todo el semestre, así
    // que es la pantalla que más necesitaba buscador y la única que no lo
    // tenía.
    final overdueTasks = appState.overdueTasks
        .where((task) => TaskSearchDialog.matches(task, _searchQuery))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tareas Vencidas'),
                if (overdueTasks.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${overdueTasks.length}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
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
                  ? Theme.of(context).primaryColor
                  : null,
            ),
            onPressed: _showSearchDialog,
            tooltip: 'Buscar',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAppInfo(),
            tooltip: 'Acerca de',
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
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'mark_all_completed') {
                _markAllAsCompleted(overdueTasks, appState);
              } else if (value == 'delete_completed') {
                _deleteCompletedTasks(overdueTasks, appState);
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
      body: appState.isLoading && overdueTasks.isEmpty
          ? ListView.builder(
              itemCount: 3,
              itemBuilder: (context, index) => const SkeletonTaskCard(),
            )
          : overdueTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _searchQuery.isEmpty
                            ? 'No hay tareas vencidas'
                            : 'Sin resultados para tu búsqueda',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      if (_searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => setState(() => _searchQuery = ''),
                          icon: const Icon(Icons.clear_rounded, size: 20),
                          label: const Text('Limpiar búsqueda'),
                        ),
                      ],
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => appState.forceSync(),
                  child: Column(
                    children: [
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
                            const Icon(Icons.warning_amber_rounded, color: AppColors.rojo),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Tienes ${overdueTasks.length} tarea(s) con fecha límite vencida. Completa o entrega para organizarlas.',
                                style: const TextStyle(
                                  color: AppColors.rojo,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: overdueTasks.length,
                          itemBuilder: (context, index) {
                            final task = overdueTasks[index];
                            return StaggeredEntrance(
                              index: index,
                              child: TaskCard(
                                task: task,
                                onTap: () => TaskDetailsDialog.show(
                                  context,
                                  task: task,
                                  appState: appState,
                                  isDeliveredView: false,
                                ),
                                onEdit: () => _editTask(task),
                                onDelete: () => TaskDetailsDialog.confirmDelete(
                                  context,
                                  task: task,
                                  appState: appState,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppInfo.buildLabel),
            const SizedBox(height: 8),
            const Text('Una aplicación para gestionar tus tareas académicas.'),
            const SizedBox(height: 8),
            const Text(
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

  void _editTask(Task task) {
    // AddTaskScreen has appState and saves automatically
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(task: task)),
    );
  }

  void _markAllAsCompleted(List<Task> overdueTasks, AppState appState) {
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
                for (final task in overdueTasks) {
                  if (!task.isCompleted) {
                    await appState.updateTaskStatus(task.id!, true, task.isSubmitted);
                  }
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Todas las tareas marcadas como completadas'),
                  ),
                );
              } catch (e) {
                if (context.mounted) {
                  final appException = ErrorMessages.fromBackendError(e);
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

  void _deleteCompletedTasks(List<Task> overdueTasks, AppState appState) {
    final completedTasks = overdueTasks.where((task) => task.isCompleted).toList();

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
                  await appState.deleteTask(task.id!);
                }
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${completedTasks.length} tarea(s) eliminada(s)',
                    ),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
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
