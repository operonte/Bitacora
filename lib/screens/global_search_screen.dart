import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/meeting_model.dart';
import '../models/study_file_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../services/meeting_service.dart';
import '../services/study_file_service.dart';
import '../utils/input_sanitizer.dart';
import '../widgets/task_details_dialog.dart';
import 'add_meeting_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Busca en tareas, reuniones y archivos a la vez.
///
/// Cada una de las tres ya tenía su propio buscador, pero cada uno solo
/// mira su propia lista — si no te acordás si algo era una tarea o quedó
/// como archivo adjunto, tenías que probar en varias pantallas. Esta no trae
/// nada nuevo del servidor: filtra sobre lo que ya está cargado en memoria
/// (AppState, MeetingService, StudyFileService), así que no hace ninguna
/// consulta nueva.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

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

    final hasResults =
        tasks.isNotEmpty || meetings.isNotEmpty || files.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar en tareas, reuniones y archivos...',
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
