import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../services/career_service.dart';

/// Todas mis notas, agrupadas por asignatura, en una tabla compacta con el
/// promedio de cada una y el promedio total. La nota y el comentario del
/// docente ya viajan con cada [Task] (los pone
/// `SupabaseDbService.applyCurrentUserProgress`) — esta pantalla no trae
/// nada nuevo del servidor, solo junta y promedia lo que ya está cargado.
///
/// Acotada al semestre actual: si cambiaste de semestre, una nota de una
/// asignatura de un semestre anterior no debería seguir apareciendo acá.
/// Igual que en `add_task_screen.dart`, si la asignatura no tiene semestre
/// etiquetado (o es una materia propia, fuera del catálogo de la carrera) se
/// sigue mostrando — filtrar sin ese dato sería adivinar y podría esconder
/// una nota real.
class MyGradesScreen extends StatelessWidget {
  final Career career;
  const MyGradesScreen({super.key, required this.career});

  bool _enSemestreActual(String subjectName, String? semestreActual) {
    if (semestreActual == null) return true;
    final coincidencias = career.predefinedSubjects.where(
      (s) => s.name == subjectName,
    );
    if (coincidencias.isEmpty) return true;
    return coincidencias.any(
      (s) => (s.semester?.isEmpty ?? true) || s.semester == semestreActual,
    );
  }

  double? _parseGrade(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.'));

  double? _promedioDe(List<Task> tasks) {
    final numeros = tasks
        .map((t) => _parseGrade(t.grade!))
        .whereType<double>()
        .toList();
    if (numeros.isEmpty) return null;
    return numeros.reduce((a, b) => a + b) / numeros.length;
  }

  @override
  Widget build(BuildContext context) {
    final semestreActual = CareerService().semesterFor(career.id);
    final tasks = context.watch<AppState>().tasks.where((t) {
      final hasGrade = t.grade?.isNotEmpty ?? false;
      if (!hasGrade || t.careerId != career.id) return false;
      return _enSemestreActual(t.subject, semestreActual);
    }).toList();

    final porAsignatura = <String, List<Task>>{};
    for (final t in tasks) {
      porAsignatura.putIfAbsent(t.subject, () => []).add(t);
    }
    final asignaturas = porAsignatura.keys.toList()..sort();

    final promedios = {
      for (final s in asignaturas) s: _promedioDe(porAsignatura[s]!),
    };
    final promediosNumericos = promedios.values.whereType<double>().toList();
    final promedioTotal = promediosNumericos.isEmpty
        ? null
        : promediosNumericos.reduce((a, b) => a + b) /
              promediosNumericos.length;

    return Scaffold(
      appBar: AppBar(title: Text('Mis notas — ${career.name}')),
      body: tasks.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  semestreActual == null
                      ? 'Todavía no tienes notas en esta carrera.'
                      : 'Todavía no tienes notas en esta carrera para el '
                            'semestre $semestreActual.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Promedio total',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        promedioTotal == null
                            ? '—'
                            : promedioTotal.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 36,
                      dataRowMinHeight: 34,
                      dataRowMaxHeight: 34,
                      columnSpacing: 24,
                      horizontalMargin: 16,
                      headingTextStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                      dataTextStyle: const TextStyle(fontSize: 12.5),
                      columns: const [
                        DataColumn(label: Text('Asignatura')),
                        DataColumn(label: Text('Notas')),
                        DataColumn(label: Text('Promedio')),
                      ],
                      rows: asignaturas.map((s) {
                        final propias = porAsignatura[s]!;
                        final promedio = promedios[s];
                        return DataRow(
                          onSelectChanged: (_) =>
                              _showSubjectGrades(context, s, propias),
                          cells: [
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 160,
                                ),
                                child: Text(
                                  s,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text('${propias.length}')),
                            DataCell(
                              Text(
                                promedio == null
                                    ? '—'
                                    : promedio.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Toca una asignatura para ver el detalle de cada nota.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
    );
  }

  void _showSubjectGrades(
    BuildContext context,
    String subject,
    List<Task> tasks,
  ) {
    final ordenadas = [...tasks]
      ..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Text(
              subject,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            for (final task in ordenadas)
              Card(
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
          ],
        ),
      ),
    );
  }
}
