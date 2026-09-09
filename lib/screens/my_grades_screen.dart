import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../widgets/subject_group_list.dart';

/// Todas mis notas juntas, agrupadas por asignatura. La nota y el comentario
/// del docente ya viajan con cada [Task] (los pone
/// `SupabaseDbService.applyCurrentUserProgress` y hoy se ven sueltos, tarea
/// por tarea, en cada [TaskCard]) — esta pantalla no trae nada nuevo del
/// servidor, solo junta lo que ya está cargado en un solo lugar para no
/// tener que ir tarea por tarea a buscarlas.
class MyGradesScreen extends StatelessWidget {
  final Career career;
  const MyGradesScreen({super.key, required this.career});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<AppState>().tasks.where((t) {
      final hasGrade = t.grade?.isNotEmpty ?? false;
      return hasGrade && t.careerId == career.id;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text('Mis notas — ${career.name}')),
      body: tasks.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Todavía no tenés notas en esta carrera.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
              ),
            )
          : SubjectGroupList<Task>(
              items: tasks,
              subjectOf: (t) => t.subject,
              countLabelOf: (n) => n == 1 ? '1 nota' : '$n notas',
              dateOf: (t) => t.dueDate,
              dateDescending: true,
              itemBuilder: (task) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(
                    task.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: task.teacherComment?.isNotEmpty ?? false
                      ? Text(task.teacherComment!)
                      : Text(
                          DateFormat('d MMM yyyy', 'es').format(task.dueDate),
                        ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      task.grade!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
