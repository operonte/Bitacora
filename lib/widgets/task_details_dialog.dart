import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/task_model.dart';
import '../models/study_file_model.dart';
import '../providers/app_state.dart';
import '../services/supabase_db_service.dart';
import '../services/study_file_service.dart';
import '../utils/error_handler.dart';
import '../utils/input_sanitizer.dart';

/// Comentarios de feedback guardados por el docente para no reescribir lo
/// mismo en cada entrega ("falta la bibliografía", "revisa el punto 3").
/// Por dispositivo, vía SharedPreferences: es una lista de atajos personales,
/// no un dato que otro miembro de la carrera necesite ver.
class _CommentTemplates {
  static const _key = 'teacher_comment_templates';

  static Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return List<String>.from(jsonDecode(raw) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = await load();
    if (current.contains(trimmed)) return;
    current.add(trimmed);
    await prefs.setString(_key, jsonEncode(current));
  }

  static Future<void> remove(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await load()
      ..remove(text);
    await prefs.setString(_key, jsonEncode(current));
  }
}

/// Diálogo de detalle de una tarea, con checkboxes de estado.
///
/// Estaba copiado tres veces entre pending/overdue/delivered_tasks_screen,
/// idéntico salvo en cuándo avisa el cambio de estado: pending y overdue
/// avisan al *entrar* a Entregadas (las dos casillas quedan en true);
/// delivered avisa al *salir* (alguna vuelve a false). Eso es lo único que
/// varía con [isDeliveredView].
class TaskDetailsDialog {
  static void show(
    BuildContext context, {
    required Task task,
    required AppState appState,
    required bool isDeliveredView,
  }) {
    var localCompleted = task.isCompleted;
    var localSubmitted = task.isSubmitted;

    Future<void> updateStatus(
      bool completed,
      bool submitted,
      void Function(void Function()) setDialogState,
    ) async {
      final success = await appState.updateTaskStatus(
        task.id!,
        completed,
        submitted,
      );
      if (!context.mounted) return;
      if (!success) {
        ErrorHandler.showErrorSnackBar(
          context,
          AppException(type: AppErrorType.unknown, message: appState.error),
        );
        return;
      }
      setDialogState(() {
        localCompleted = completed;
        localSubmitted = submitted;
      });

      final entregada = completed && submitted;
      final saleDeEntregada = !completed || !submitted;
      if (isDeliveredView ? saleDeEntregada : entregada) {
        Navigator.pop(context);
        if (!isDeliveredView) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Tarea movida a Entregadas'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }

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
                Text('Creado por: ${task.userName}'),
                Text('Tipo: ${task.type}'),
                Text(
                  'Entrega: ${DateFormat('dd/MM/yyyy HH:mm').format(task.dueDate)}',
                ),
                const SizedBox(height: 8),
                Text('Descripción: ${task.description}'),
                if ((task.grade?.isNotEmpty ?? false) ||
                    (task.teacherComment?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Del docente:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (task.grade?.isNotEmpty ?? false)
                    Text('Nota: ${task.grade}'),
                  if (task.teacherComment?.isNotEmpty ?? false)
                    Text(
                      '"${task.teacherComment}"',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
                if (task.id != null) _AttachedFilesSection(task: task),
                const SizedBox(height: 16),
                const Text(
                  'Estado:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Realizada'),
                  value: localCompleted,
                  onChanged: (value) async {
                    if (value != null) {
                      await updateStatus(value, localSubmitted, setDialogState);
                    }
                  },
                  activeColor: Colors.green,
                ),
                CheckboxListTile(
                  title: const Text('Enviada'),
                  value: localSubmitted,
                  onChanged: (value) async {
                    if (value != null) {
                      await updateStatus(localCompleted, value, setDialogState);
                    }
                  },
                  activeColor: Colors.green,
                ),
                if (isDeliveredView)
                  if (localCompleted && localSubmitted)
                    _banner(
                      Icons.check_circle,
                      Colors.green,
                      'Tarea completamente entregada',
                    )
                  else
                    const SizedBox.shrink()
                else if (localCompleted && !localSubmitted)
                  _banner(
                    Icons.warning,
                    Colors.orange,
                    'Realizada pero no enviada',
                  ),
              ],
            );
          },
        ),
        actions: [
          // Solo quien creó la tarea la ve: el RPC del servidor exige lo
          // mismo, esto solo evita mostrar un botón que va a fallar.
          if (task.isShared &&
              task.userId == Supabase.instance.client.auth.currentUser?.id)
            TextButton(
              onPressed: () => _showSubmissionStatus(context, task),
              child: const Text('Ver progreso del grupo'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  /// Quién de la carrera marcó esta tarea realizada/enviada. Solo tiene
  /// sentido para quien la creó — es lo que exige get_task_submission_status
  /// en el servidor; ver [show] arriba.
  static void _showSubmissionStatus(BuildContext context, Task task) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var future = SupabaseDbService().getTaskSubmissionStatus(task.id!);
          void refresh() => setDialogState(() {
            future = SupabaseDbService().getTaskSubmissionStatus(task.id!);
          });

          return AlertDialog(
            title: Text('Progreso — ${task.title}'),
            content: SizedBox(
              width: double.maxFinite,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'No se pudo cargar el progreso: ${snapshot.error}',
                      ),
                    );
                  }
                  final rows = snapshot.data ?? [];
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Todavía nadie más pertenece a esta carrera.',
                      ),
                    );
                  }
                  return ListView(
                    shrinkWrap: true,
                    children: rows
                        .map(
                          (r) => _submissionTile(context, task.id!, r, refresh),
                        )
                        .toList(),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _submissionTile(
    BuildContext context,
    String taskId,
    Map<String, dynamic> row,
    VoidCallback onCommentSaved,
  ) {
    final completed = row['is_completed'] as bool? ?? false;
    final submitted = row['is_submitted'] as bool? ?? false;
    final displayName = (row['display_name'] as String?)?.trim();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : (row['email'] as String? ?? 'Sin nombre');
    final studentUserId = row['user_id'].toString();
    final comment = (row['teacher_comment'] as String?)?.trim();
    final grade = (row['grade'] as String?)?.trim();
    final hasFeedback =
        (comment?.isNotEmpty ?? false) || (grade?.isNotEmpty ?? false);

    late final IconData icon;
    late final Color color;
    late final String label;
    if (completed && submitted) {
      icon = Icons.check_circle;
      color = Colors.green;
      label = 'Entregada';
    } else if (completed) {
      icon = Icons.warning_amber_rounded;
      color = Colors.orange;
      label = 'Realizada, no enviada';
    } else {
      icon = Icons.radio_button_unchecked;
      color = Colors.grey;
      label = 'Pendiente';
    }

    final subtitleParts = [
      label,
      if (grade?.isNotEmpty ?? false) 'Nota: $grade',
      if (comment?.isNotEmpty ?? false) '"$comment"',
    ];

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(name),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: hasFeedback
            ? const TextStyle(fontStyle: FontStyle.italic)
            : null,
      ),
      trailing: IconButton(
        icon: Icon(
          hasFeedback ? Icons.comment : Icons.comment_outlined,
          size: 18,
        ),
        tooltip: 'Nota y comentario',
        onPressed: () => _editCommentDialog(
          context,
          taskId: taskId,
          studentUserId: studentUserId,
          studentName: name,
          initialComment: comment ?? '',
          initialGrade: grade ?? '',
          onSaved: onCommentSaved,
        ),
      ),
    );
  }

  static Future<void> _editCommentDialog(
    BuildContext context, {
    required String taskId,
    required String studentUserId,
    required String studentName,
    required String initialComment,
    required String initialGrade,
    required VoidCallback onSaved,
  }) async {
    final controller = TextEditingController(text: initialComment);
    final gradeController = TextEditingController(text: initialGrade);
    var templates = await _CommentTemplates.load();

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Nota y comentario para $studentName'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: gradeController,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: 'Nota (opcional)',
                    hintText: 'Ej: 6.5, Aprobado, 18/20',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    hintText: 'Ej: falta la bibliografía',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (templates.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Plantillas',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: templates
                        .map(
                          (t) => InputChip(
                            label: Text(t, overflow: TextOverflow.ellipsis),
                            onPressed: () => controller.text = t,
                            onDeleted: () async {
                              await _CommentTemplates.remove(t);
                              setLocal(
                                () => templates = templates
                                    .where((x) => x != t)
                                    .toList(),
                              );
                            },
                          ),
                        )
                        .toList(),
                  ),
                ],
                TextButton.icon(
                  onPressed: () async {
                    await _CommentTemplates.add(controller.text);
                    setLocal(() {});
                    final refreshed = await _CommentTemplates.load();
                    setLocal(() => templates = refreshed);
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: const Text('Guardar como plantilla'),
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
                try {
                  final service = SupabaseDbService();
                  await service.setTaskTeacherComment(
                    taskId,
                    studentUserId,
                    controller.text,
                  );
                  await service.setTaskGrade(
                    taskId,
                    studentUserId,
                    gradeController.text,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  onSaved();
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('No se pudo guardar: $e')),
                    );
                  }
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _banner(IconData icon, Color color, String text) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );

  /// Confirma y borra una tarea. Copiado idéntico en las tres pantallas.
  static void confirmDelete(
    BuildContext context, {
    required Task task,
    required AppState appState,
  }) {
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
                final success = await appState.deleteTask(task.id!);
                if (!context.mounted) return;
                if (!success) {
                  ErrorHandler.showErrorSnackBar(
                    context,
                    AppException(
                      type: AppErrorType.unknown,
                      message: appState.error,
                    ),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
                );
              } catch (e) {
                if (context.mounted) {
                  final appException = ErrorMessages.fromBackendError(e);
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

/// Archivos de "Mis archivos" adjuntados a esta tarea. Adjuntar no sube nada
/// nuevo — enlaza un archivo que ya subiste por su flujo normal, así no hay
/// que reimplementar la subida a Drive acá adentro.
class _AttachedFilesSection extends StatefulWidget {
  final Task task;
  const _AttachedFilesSection({required this.task});

  @override
  State<_AttachedFilesSection> createState() => _AttachedFilesSectionState();
}

class _AttachedFilesSectionState extends State<_AttachedFilesSection> {
  final _service = StudyFileService();

  List<StudyFile> get _attached => _service
      .getFiles(category: StudyFileCategory.trabajo)
      .where((f) => f.taskId == widget.task.id)
      .toList();

  Future<void> _attach() async {
    final candidatos = _service
        .getFiles(category: StudyFileCategory.trabajo)
        .where(
          (f) => f.subject == widget.task.subject && f.taskId != widget.task.id,
        )
        .toList();

    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No tenés archivos de "${widget.task.subject}" en Mis archivos. Subilo ahí primero y después volvé a adjuntarlo acá.',
          ),
        ),
      );
      return;
    }

    final elegido = await showDialog<StudyFile>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Adjuntar archivo'),
        children: candidatos
            .map(
              (f) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, f),
                child: Row(
                  children: [
                    Icon(f.fileIcon, color: f.fileColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.name)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
    if (elegido == null) return;

    await _service.saveFile(elegido.copyWith(taskId: widget.task.id));
    if (mounted) setState(() {});
  }

  Future<void> _detach(StudyFile file) async {
    await _service.saveFile(file.copyWith(clearTaskId: true));
    if (mounted) setState(() {});
  }

  Future<void> _open(StudyFile file) async {
    final url = file.openUrl;
    if (url.isEmpty || !InputSanitizer.isSafeExternalUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este archivo no tiene un enlace válido.'),
        ),
      );
      return;
    }
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir el archivo: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attached = _attached;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Archivos:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _attach,
              icon: const Icon(Icons.attach_file, size: 16),
              label: const Text('Adjuntar'),
            ),
          ],
        ),
        if (attached.isEmpty)
          const Text(
            'Ninguno todavía.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else
          for (final f in attached)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(f.fileIcon, color: f.fileColor, size: 20),
              title: Text(f.name, style: const TextStyle(fontSize: 13)),
              onTap: () => _open(f),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Quitar',
                onPressed: () => _detach(f),
              ),
            ),
      ],
    );
  }
}
