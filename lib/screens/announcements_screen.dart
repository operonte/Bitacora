import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../colors.dart';
import '../models/announcement_model.dart';
import '../models/career_model.dart';
import '../services/admin_auth_service.dart';
import '../services/announcement_service.dart';
import '../services/career_service.dart';

/// Anuncios de la carrera: lo que hoy se manda por WhatsApp aparte, dentro
/// de la app. Un docente publica, todos los miembros lo ven — y si es
/// urgente, además suena (mientras la app esté abierta; ver
/// [AnnouncementService]).
class AnnouncementsScreen extends StatefulWidget {
  final Career career;
  const AnnouncementsScreen({super.key, required this.career});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _service = AnnouncementService();
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _service.loadFor(widget.career.id);
    AdminAuthService.isCurrentUserAdmin().then((v) {
      if (mounted) setState(() => _isAdmin = v);
    });
  }

  @override
  void dispose() {
    _service.stopWatching();
    super.dispose();
  }

  String _relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'recién';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'hace ${diff.inDays} d';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDelete(Announcement a, {required bool asAdmin}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar anuncio?'),
        content: Text(
          asAdmin
              ? '"${a.title}" es de ${a.createdByName}. Se borrará para toda la carrera.'
              : '"${a.title}" se borrará para toda la carrera.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (asAdmin) {
        await AdminAuthService.deleteAnnouncement(a.id!);
        await _service.loadFor(widget.career.id);
      } else {
        await _service.delete(a.id!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String? subject;
    var urgent = false;
    final subjects =
        widget.career.predefinedSubjects.map((s) => s.name).toSet().toList()
          ..sort();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Nuevo anuncio'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Título',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: bodyController,
                  maxLines: 3,
                  maxLength: 800,
                  decoration: const InputDecoration(
                    labelText: 'Detalle (opcional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: subject,
                  decoration: const InputDecoration(
                    labelText: 'Asignatura',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toda la carrera'),
                    ),
                    ...subjects.map(
                      (s) =>
                          DropdownMenuItem<String?>(value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (v) => setLocal(() => subject = v),
                ),
                SwitchListTile(
                  value: urgent,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Urgente'),
                  subtitle: const Text(
                    'Además de aparecer en la lista, suena como notificación',
                    style: TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => setLocal(() => urgent = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                final user = Supabase.instance.client.auth.currentUser;
                if (user == null) return;
                final name =
                    (user.userMetadata?['full_name'] as String?)
                            ?.trim()
                            .isNotEmpty ==
                        true
                    ? user.userMetadata!['full_name'] as String
                    : 'Docente';
                try {
                  await _service.create(
                    Announcement(
                      careerId: widget.career.id,
                      subject: subject,
                      title: title,
                      body: bodyController.text.trim(),
                      urgent: urgent,
                      createdBy: user.id,
                      createdByName: name,
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('No se pudo publicar: $e')),
                    );
                  }
                }
              },
              child: const Text('Publicar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDocente = CareerService().isDocente(widget.career.id);
    final uid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: Text('Anuncios — ${widget.career.name}')),
      body: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final items = _service.announcements;
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary.withValues(alpha: 0.15),
                            AppColors.accentTeal.withValues(alpha: 0.15),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.campaign_outlined,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Todavía no hay anuncios en esta carrera',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = items[i];
              final accent = a.urgent ? AppColors.error : AppColors.accentTeal;
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 5, color: accent),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      a.urgent
                                          ? Icons.priority_high_rounded
                                          : Icons.campaign_outlined,
                                      size: 16,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      a.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (a.createdBy == uid || _isAdmin)
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: AppColors.error,
                                      ),
                                      onPressed: () => _confirmDelete(
                                        a,
                                        asAdmin: a.createdBy != uid,
                                      ),
                                      tooltip: 'Eliminar',
                                    ),
                                ],
                              ),
                              if (a.body.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  a.body,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  a.subject ?? 'Toda la carrera',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${a.createdByName} · ${_relative(a.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isDocente
          ? FloatingActionButton(
              onPressed: _openCreateDialog,
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.campaign_outlined, color: Colors.white),
            )
          : null,
    );
  }
}
