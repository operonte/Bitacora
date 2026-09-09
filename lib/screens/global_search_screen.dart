import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../models/meeting_model.dart';
import '../models/study_file_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../services/career_service.dart';
import '../services/meeting_service.dart';
import '../services/study_file_service.dart';
import '../services/supabase_db_service.dart';
import '../utils/input_sanitizer.dart';
import '../widgets/task_details_dialog.dart';
import 'add_meeting_screen.dart';
import 'student_profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Un alumno encontrado, con la carrera en la que se lo busca — hace falta
/// para poder abrir su Ficha después.
class _StudentHit {
  final Career career;
  final String userId;
  final String name;
  final String email;
  _StudentHit({
    required this.career,
    required this.userId,
    required this.name,
    required this.email,
  });
}

/// Busca en tareas, reuniones, archivos y —si sos docente— alumnos, a la vez.
///
/// Tareas, reuniones y archivos ya tenían su propio buscador, pero cada uno
/// solo mira su propia lista — si no te acordás si algo era una tarea o
/// quedó como archivo adjunto, tenías que probar en varias pantallas. Esos
/// tres no traen nada nuevo del servidor: filtran sobre lo que ya está
/// cargado en memoria (AppState, MeetingService, StudyFileService).
///
/// Los alumnos son la excepción: no hay una lista de alumnos ya cargada en
/// ningún lado, así que al abrir la pantalla se pide una sola vez (por cada
/// carrera donde sos docente) y se filtra en memoria de ahí en más — no se
/// vuelve a pedir en cada letra que se tipea.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  /// Null mientras se está cargando (o si no sos docente en ninguna
  /// carrera, se queda en lista vacía).
  List<_StudentHit>? _students;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    final misCarreras = CareerService()
        .getCareers()
        .where((c) => CareerService().isDocente(c.id))
        .toList();
    if (misCarreras.isEmpty) {
      if (mounted) setState(() => _students = []);
      return;
    }

    final hits = <_StudentHit>[];
    for (final career in misCarreras) {
      try {
        final rows = await SupabaseDbService().getStudentRisk(career.id);
        for (final r in rows) {
          final displayName = (r['display_name'] as String?)?.trim();
          final email = (r['email'] as String?) ?? '';
          hits.add(
            _StudentHit(
              career: career,
              userId: r['user_id'].toString(),
              name: (displayName != null && displayName.isNotEmpty)
                  ? displayName
                  : (email.isNotEmpty ? email : 'Sin nombre'),
              email: email,
            ),
          );
        }
      } catch (_) {
        // Sin red: esta carrera queda afuera de la búsqueda por ahora, el
        // resto (tareas/reuniones/archivos) sigue andando igual.
      }
    }
    if (mounted) setState(() => _students = hits);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(String query, List<String> fields) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return false;
    return fields.any((f) => f.toLowerCase().contains(q));
  }

  Future<void> _openLink(String url) async {
    if (url.isEmpty || !InputSanitizer.isSafeExternalUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este enlace no es válido.')),
      );
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo abrir: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final tasks = _query.isEmpty
        ? const <Task>[]
        : appState.tasks
              .where(
                (t) => _matches(_query, [t.title, t.subject, t.description]),
              )
              .toList();
    final meetings = _query.isEmpty
        ? const <Meeting>[]
        : MeetingService()
              .getMeetings()
              .where((m) => _matches(_query, [m.title, m.subject, m.professor]))
              .toList();
    final files = _query.isEmpty
        ? const <StudyFile>[]
        : [
            ...StudyFileService().getFiles(category: StudyFileCategory.trabajo),
            ...StudyFileService().getFiles(category: StudyFileCategory.guia),
          ].where((f) => _matches(_query, [f.name, f.subject])).toList();
    final students = _query.isEmpty || _students == null
        ? const <_StudentHit>[]
        : _students!.where((s) => _matches(_query, [s.name, s.email])).toList();

    final hasResults =
        tasks.isNotEmpty ||
        meetings.isNotEmpty ||
        files.isNotEmpty ||
        students.isNotEmpty;
    final esDocente = (_students?.isNotEmpty ?? false);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: esDocente
                ? 'Buscar tareas, reuniones, archivos o alumnos...'
                : 'Buscar en tareas, reuniones y archivos...',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 16),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() {
                _controller.clear();
                _query = '';
              }),
            ),
        ],
      ),
      body: _query.isEmpty
          ? const Center(
              child: Text(
                'Escribí para buscar en todo lo tuyo.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : !hasResults
          ? const Center(
              child: Text(
                'Sin resultados.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (tasks.isNotEmpty) ...[
                  _sectionHeader('Tareas', Icons.checklist_rtl),
                  for (final t in tasks)
                    ListTile(
                      leading: const Icon(Icons.task_alt_outlined),
                      title: Text(t.title),
                      subtitle: Text(t.subject),
                      onTap: () => TaskDetailsDialog.show(
                        context,
                        task: t,
                        appState: appState,
                        isDeliveredView: t.isCompleted && t.isSubmitted,
                      ),
                    ),
                ],
                if (meetings.isNotEmpty) ...[
                  _sectionHeader('Reuniones', Icons.event_note_outlined),
                  for (final m in meetings)
                    ListTile(
                      leading: Icon(m.typeIcon),
                      title: Text(m.title),
                      subtitle: Text(
                        '${m.subject} · ${DateFormat('d MMM HH:mm', 'es').format(m.effectiveDate)}',
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddMeetingScreen(meeting: m),
                        ),
                      ),
                    ),
                ],
                if (files.isNotEmpty) ...[
                  _sectionHeader('Archivos', Icons.folder_outlined),
                  for (final f in files)
                    ListTile(
                      leading: Icon(f.fileIcon, color: f.fileColor),
                      title: Text(f.name),
                      subtitle: Text(f.subject),
                      onTap: () => _openLink(f.openUrl),
                    ),
                ],
                if (students.isNotEmpty) ...[
                  _sectionHeader('Alumnos', Icons.person_search_outlined),
                  for (final s in students)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(s.name),
                      subtitle: Text(s.career.name),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StudentProfileScreen(
                            career: s.career,
                            studentId: s.userId,
                            studentName: s.name,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _sectionHeader(String label, IconData icon) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    ),
  );
}
