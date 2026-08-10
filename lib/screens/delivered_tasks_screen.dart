import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/task_search_dialog.dart';
import '../widgets/task_details_dialog.dart';
import 'add_task_screen.dart';
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
    final allDeliveredTasks = appState.deliveredTasks;

    final deliveredTasks = allDeliveredTasks
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
                          onTap: () => TaskDetailsDialog.show(
                            context,
                            task: task,
                            appState: appState,
                            isDeliveredView: true,
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
    );
  }

  void _editTask(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(task: task)),
    );
  }
}
