import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/task_model.dart';
import '../widgets/task_card.dart';
import '../widgets/staggered_entrance.dart';
import '../widgets/task_search_dialog.dart';
import '../widgets/task_details_dialog.dart';
import '../widgets/mascot_widget.dart';
import '../widgets/subject_filter_chips.dart';
import '../widgets/completion_rate_banner.dart';
import '../widgets/month_calendar_grid.dart';
import 'global_search_screen.dart';
import '../providers/theme_provider.dart';
import 'add_task_screen.dart';
import 'assign_task_screen.dart';
import '../colors.dart';
import '../services/career_service.dart';
import '../services/sync_service.dart';
import 'config_screen.dart';
import 'my_profile_screen.dart';

class PendingTasksScreen extends StatefulWidget {
  const PendingTasksScreen({super.key});

  @override
  State<PendingTasksScreen> createState() => _PendingTasksScreenState();
}

class _PendingTasksScreenState extends State<PendingTasksScreen> {
  String _selectedSubject = SubjectFilterChips.all;
  String _searchQuery = '';
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);

  void _changeMonth(int delta) {
    setState(() {
      _monthCursor = DateTime(_monthCursor.year, _monthCursor.month + delta);
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';
    final viewMode = context.watch<ThemeProvider>().tasksViewMode;

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
            icon: const Icon(Icons.manage_search),
            tooltip: 'Buscar en todo (tareas, reuniones, archivos)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.search,
              color: _searchQuery.isNotEmpty
                  ? Theme.of(context).primaryColor
                  : null,
            ),
            onPressed: _showSearchDialog,
            tooltip: 'Buscar en pendientes',
          ),
          SyncIndicator(syncService: SyncService()),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyProfileScreen()),
            ),
            tooltip: 'Mi perfil',
          ),
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
                : viewMode == TasksViewMode.week
                ? _buildWeekAgenda(context, appState, filteredTasks)
                : viewMode == TasksViewMode.month
                ? _buildMonthView(context, appState, filteredTasks)
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

  /// Los próximos 7 días, uno debajo del otro con su fecha — a diferencia de
  /// reuniones, una tarea no tiene una hora fija que justifique una grilla
  /// horizontal, así que acá "semana" es una agenda vertical.
  Widget _buildWeekAgenda(
    BuildContext context,
    AppState appState,
    List<Task> tasks,
  ) {
    final today = DateTime.now();
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(today.year, today.month, today.day + i),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE d MMM', 'es').format(day),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isSameDay(day, today)
                        ? Theme.of(context).primaryColor
                        : context.textSecondaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: Divider(color: context.borderColor)),
              ],
            ),
          ),
          ...() {
            final delDia = tasks
                .where((t) => _isSameDay(t.dueDate, day))
                .toList();
            if (delDia.isEmpty) {
              return [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Libre',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              ];
            }
            return delDia
                .map((t) => _CompactTaskTile(task: t, appState: appState))
                .toList();
          }(),
        ],
      ],
    );
  }

  Widget _buildMonthView(
    BuildContext context,
    AppState appState,
    List<Task> tasks,
  ) {
    final byDay = <DateTime, List<Task>>{};
    for (final t in tasks) {
      final day = DateTime(t.dueDate.year, t.dueDate.month, t.dueDate.day);
      byDay.putIfAbsent(day, () => []).add(t);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        MonthCalendarGrid<Task>(
          monthCursor: _monthCursor,
          onMonthDelta: _changeMonth,
          itemsByDay: byDay,
          colorOf: (t) => SubjectColorHelper.colorFor(t.subject),
          onDayTap: (tasksThatDay) => showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final t in tasksThatDay)
                    _CompactTaskTile(task: t, appState: appState),
                ],
              ),
            ),
          ),
        ),
      ],
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
    final career = CareerService().getSelectedCareer();
    if (career != null && CareerService().isDocente(career.id)) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AssignTaskScreen(career: career),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddTaskScreen()),
    );
  }

  void _editTask(Task task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AssignTaskScreen.editorFor(task) ?? AddTaskScreen(task: task),
      ),
    );
  }
}

/// Fila compacta para la vista de semana y el detalle de un día del mes —
/// la tarjeta completa (TaskCard) es demasiado alta para listar varios días
/// seguidos en una sola pantalla.
class _CompactTaskTile extends StatelessWidget {
  final Task task;
  final AppState appState;
  const _CompactTaskTile({required this.task, required this.appState});

  @override
  Widget build(BuildContext context) {
    final urgency = task.getUrgency();
    final color = TaskColorHelper.getUrgencyColor(urgency);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: SubjectColorHelper.colorFor(task.subject),
        ),
      ),
      title: Text(
        task.title,
        style: TextStyle(
          decoration: (task.isCompleted && task.isSubmitted)
              ? TextDecoration.lineThrough
              : null,
        ),
      ),
      subtitle: Text(task.subject),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          DateFormat('HH:mm').format(task.dueDate),
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: () => TaskDetailsDialog.show(
        context,
        task: task,
        appState: appState,
        isDeliveredView: false,
      ),
    );
  }
}
