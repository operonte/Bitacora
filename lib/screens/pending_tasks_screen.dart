import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import '../providers/app_state.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/task_search_dialog.dart';
import '../widgets/task_details_dialog.dart';
import '../widgets/mascot_widget.dart';
import '../widgets/subject_filter_chips.dart';
import '../widgets/completion_rate_banner.dart';
import '../providers/theme_provider.dart';
import 'add_task_screen.dart';
import '../colors.dart';
import '../services/career_service.dart';
import '../services/sync_service.dart';
import 'config_screen.dart';

class PendingTasksScreen extends StatefulWidget {
  const PendingTasksScreen({super.key});

  @override
  State<PendingTasksScreen> createState() => _PendingTasksScreenState();
}

class _PendingTasksScreenState extends State<PendingTasksScreen> {
  String _selectedSubject = SubjectFilterChips.all;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';

    final appState = context.watch<AppState>();
    final allPendingTasks = appState.pendingTasks;

    // Filtrar tareas por materia y búsqueda
    final filteredTasks = allPendingTasks
        .where((task) => SubjectFilterChips.matches(task, _selectedSubject))
        .where((task) => TaskSearchDialog.matches(task, _searchQuery))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tareas Pendientes'),
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
      body: Column(
        children: [
          CompletionRateBanner(
            delivered: appState.deliveredTasks.length,
            overdue: appState.overdueTasks.length,
          ),
          SubjectFilterChips(
            tasks: allPendingTasks,
            selected: _selectedSubject,
            onSelected: (subject) => setState(() => _selectedSubject = subject),
          ),
          Expanded(
            child: appState.isLoading && allPendingTasks.isEmpty
                ? ListView.builder(
                    itemCount: 3,
                    itemBuilder: (context, index) => const SkeletonTaskCard(),
                  )
                : filteredTasks.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () => appState.forceSync(),
                    child: ListView.builder(
                      itemCount: filteredTasks.length,
                      itemBuilder: (context, index) {
                        final task = filteredTasks[index];
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
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildEmptyState() {
    final primaryIconColor = Theme.of(context).primaryColor;
    final mascot = context.watch<ThemeProvider>().mascot;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MascotWidget.isEnabled(mascot))
              MascotWidget(
                option: mascot,
                state: MascotState.content,
                size: 120,
              )
            else
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: primaryIconColor.withValues(
                    alpha: context.isDark ? 0.15 : 0.08,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.task_alt_rounded,
                  size: 64,
                  color: primaryIconColor,
                ),
              ),
            const SizedBox(height: 24),
            Text(
              '¡Todo al día!',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No se encontraron tareas para tu búsqueda.'
                  : 'No tienes tareas pendientes.\nAgrega una nueva para empezar.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 28),
            if (_searchQuery.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () => setState(() => _searchQuery = ''),
                icon: const Icon(Icons.clear_rounded, size: 20),
                label: const Text('Limpiar búsqueda'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIconColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                onPressed: _addTask,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Nueva tarea'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIconColor,
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

  Future<void> _showSearchDialog() async {
    final query = await TaskSearchDialog.show(context, _searchQuery);
    if (query == null || !mounted) return;
    setState(() => _searchQuery = query);
  }

  void _addTask() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );
  }

  void _editTask(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AddTaskScreen(task: task)),
    );
  }
}
