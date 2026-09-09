import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/meeting_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../services/announcement_service.dart';
import '../services/career_service.dart';
import '../services/meeting_service.dart';
import '../services/sync_service.dart';
import '../widgets/completion_rate_banner.dart';
import '../widgets/task_card.dart';
import '../widgets/task_details_dialog.dart';
import 'add_meeting_screen.dart';
import 'add_task_screen.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'config_screen.dart';
import 'global_search_screen.dart';
import 'teacher_panel_screen.dart';

/// Lo urgente de hoy, de un vistazo, al abrir la app.
///
/// Antes la app arrancaba directo en la lista plana de tareas pendientes, y
/// todo lo del docente vivía enterrado en Configuración → Mi progreso. Google
/// Classroom hizo exactamente este cambio en julio de 2026: pasó de una
/// grilla estática a un panel por rol. Acá el mismo criterio: si sos
/// docente, esta pantalla se ve distinta desde el primer segundo, con sus
/// herramientas a mano — no hay que ir a buscarlas.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    final career = CareerService().getSelectedCareer();
    if (career != null) {
      // Solo para que la lista de anuncios tenga algo que mostrar acá — la
      // suscripción en sí ya la sostiene AppState desde el login.
      AnnouncementService().loadFor(career.id);
    }
  }

  String get _saludo {
    final h = DateTime.now().hour;
    if (h < 12) return 'Buenos días';
    if (h < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final isDocente = CareerService().isDocente(career?.id);
    final appState = context.watch<AppState>();

    final urgentTasks = [
      ...appState.overdueTasks,
      ...appState.pendingTasks.where(
        (t) => t.getUrgency() == TaskUrgency.urgent,
      ),
    ];

    final now = DateTime.now();
    final meetingsToday =
        MeetingService()
            .getMeetings(careerId: career?.id)
            .where((m) => _isSameDay(m.effectiveDate, now))
            .toList()
          ..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));

    final announcements = AnnouncementService().announcements
        .where((a) => a.urgent)
        .take(3)
        .toList();

    final nadaUrgente =
        urgentTasks.isEmpty && meetingsToday.isEmpty && announcements.isEmpty;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(career?.name ?? 'Bitácora'),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_search),
            tooltip: 'Buscar en todo',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
            ),
          ),
          SyncIndicator(syncService: SyncService()),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfigScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => appState.forceSync(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              '$_saludo${career != null ? ',' : ''}',
              style: GoogleFonts.crimsonPro(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: context.textColor,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              nadaUrgente
                  ? 'Nada urgente por ahora.'
                  : 'Esto es lo que necesita tu atención hoy.',
              style: TextStyle(fontSize: 15, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 20),
            if (isDocente) _buildDocenteStrip(context, career!.id),
            if (announcements.isNotEmpty) ...[
              _sectionLabel('Anuncios'),
              for (final a in announcements)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: AppColors.warning.withValues(alpha: 0.08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.campaign_outlined,
                      color: AppColors.warning,
                    ),
                    title: Text(a.title),
                    subtitle: Text(
                      '${a.createdByName} · ${a.subject ?? career?.name ?? ''}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnnouncementsScreen(career: career!),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (meetingsToday.isNotEmpty) ...[
              _sectionLabel('Hoy'),
              for (final m in meetingsToday) _MeetingTile(meeting: m),
              const SizedBox(height: 12),
            ],
            if (urgentTasks.isNotEmpty) ...[
              _sectionLabel('Urgente'),
              for (final t in urgentTasks.take(6))
                TaskCard(
                  task: t,
                  onTap: () => TaskDetailsDialog.show(
                    context,
                    task: t,
                    appState: appState,
                    isDeliveredView: false,
                  ),
                  onEdit: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => AddTaskScreen(task: t)),
                  ),
                  onDelete: () => TaskDetailsDialog.confirmDelete(
                    context,
                    task: t,
                    appState: appState,
                  ),
                ),
              const SizedBox(height: 12),
            ],
            if (nadaUrgente)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  children: [
                    Icon(
                      Icons.self_improvement_outlined,
                      size: 56,
                      color: context.textSecondaryColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Todo tranquilo. Buen momento para adelantar algo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.textSecondaryColor),
                    ),
                  ],
                ),
              ),
            CompletionRateBanner(
              delivered: appState.deliveredTasks.length,
              overdue: appState.overdueTasks.length,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: GoogleFonts.crimsonPro(fontSize: 19, fontWeight: FontWeight.w700),
    ),
  );

  /// Herramientas de docente, a mano desde el primer nivel. Antes solo se
  /// llegaba a esto por Configuración → Mi progreso → un submenú — ahí es
  /// donde de verdad se siente que la app "no sirve para dar clases".
  Widget _buildDocenteStrip(BuildContext context, String careerId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.school,
                size: 18,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Herramientas de docente',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _docenteAction(
                context,
                icon: Icons.checklist_rtl,
                label: 'Asistencia',
                onTap: () {
                  final c = CareerService().getSelectedCareer();
                  if (c == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AttendanceScreen(career: c),
                    ),
                  );
                },
              ),
              _docenteAction(
                context,
                icon: Icons.warning_amber_rounded,
                label: 'Riesgo',
                onTap: () {
                  final c = CareerService().getSelectedCareer();
                  if (c == null) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeacherPanelScreen(career: c),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _docenteAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _MeetingTile extends StatelessWidget {
  final Meeting meeting;
  const _MeetingTile({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(meeting.typeIcon, color: Theme.of(context).primaryColor),
        title: Text(meeting.title),
        subtitle: Text(
          '${meeting.subject} · ${DateFormat('HH:mm').format(meeting.effectiveDate)}',
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AddMeetingScreen(meeting: meeting)),
        ),
      ),
    );
  }
}
