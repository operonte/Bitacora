import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/attendance_service.dart';
import '../services/supabase_db_service.dart';

enum _EstadoTarea { atrasada, pendiente, entregadaATiempo, entregadaTarde }

/// Ficha de un alumno puntual: sus tareas (con nota y estado) y su
/// asistencia, todo junto — el Panel de riesgo ya decía "3 tareas atrasadas
/// y 65% de asistencia", esto dice cuáles y cuándo.
class StudentProfileScreen extends StatefulWidget {
  final Career career;
  final String studentId;
  final String studentName;

  const StudentProfileScreen({
    super.key,
    required this.career,
    required this.studentId,
    required this.studentName,
  });

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  List<Map<String, dynamic>>? _tasks;
  List<Map<String, dynamic>>? _attendance;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        SupabaseDbService().getStudentTasks(widget.career.id, widget.studentId),
        AttendanceService().getStudentAttendance(
          widget.career.id,
          widget.studentId,
        ),
      ]);
      if (mounted) {
        setState(() {
          _tasks = results[0];
          _attendance = results[1];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  /// Se basa en la última escritura del progreso (task_progress.updated_at),
  /// no en el momento exacto en que pasó a completada+enviada — si alguien
  /// destildó y volvió a marcar, esa es la fecha que cuenta. Aun así es la
  /// única señal real que hay; no se inventa una fecha de entrega que la
  /// app no guarda.
  _EstadoTarea _estadoDe(Map<String, dynamic> row) {
    final dueDate = DateTime.fromMillisecondsSinceEpoch(
      (row['due_date'] as num).toInt(),
    );
    final isCompleted = row['is_completed'] == true;
    final isSubmitted = row['is_submitted'] == true;
    if (isCompleted && isSubmitted) {
      final updatedAtMs = (row['progress_updated_at'] as num?)?.toInt() ?? 0;
      final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
      return updatedAt.isAfter(dueDate)
          ? _EstadoTarea.entregadaTarde
          : _EstadoTarea.entregadaATiempo;
    }
    return dueDate.isBefore(DateTime.now())
        ? _EstadoTarea.atrasada
        : _EstadoTarea.pendiente;
  }

  (Color, String) _estadoInfo(_EstadoTarea estado) {
    switch (estado) {
      case _EstadoTarea.atrasada:
        return (AppColors.error, 'Atrasada');
      case _EstadoTarea.pendiente:
        return (AppColors.textSecondary, 'Pendiente');
      case _EstadoTarea.entregadaATiempo:
        return (AppColors.success, 'A tiempo');
      case _EstadoTarea.entregadaTarde:
        return (Colors.orange, 'Entregada tarde');
    }
  }

  Color _attendanceStatusColor(String status) {
    switch (status) {
      case 'presente':
        return AppColors.success;
      case 'tarde':
        return Colors.orange;
      case 'justificado':
        return AppColors.primary;
      case 'ausente':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _attendanceStatusLabel(String status) {
    switch (status) {
      case 'presente':
        return 'Presente';
      case 'tarde':
        return 'Tarde';
      case 'justificado':
        return 'Justificado';
      case 'ausente':
        return 'Ausente';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.studentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.error),
          ),
        ),
      );
    }
    final tasks = _tasks;
    final attendance = _attendance;
    if (tasks == null || attendance == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionLabel(context, 'Tareas', Icons.checklist_rtl),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin tareas compartidas en esta carrera todavía.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final row in tasks) _buildTaskTile(row),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Asistencia', Icons.checklist_rtl),
          const SizedBox(height: 8),
          if (attendance.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Sin asistencia registrada todavía.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            for (final entry in _groupBySubject(attendance).entries)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ExpansionTile(
                  title: Text(
                    '${entry.key} · ${entry.value.length} ${entry.value.length == 1 ? 'clase' : 'clases'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  children: [
                    for (final r in entry.value)
                      Builder(
                        builder: (context) {
                          final status =
                              r['status']?.toString() ?? 'sin_marcar';
                          final color = _attendanceStatusColor(status);
                          final date = DateTime.tryParse(
                            r['class_date']?.toString() ?? '',
                          );
                          return ListTile(
                            dense: true,
                            leading: Icon(Icons.circle, size: 12, color: color),
                            title: Text(
                              date != null
                                  ? DateFormat('EEEE d MMM', 'es').format(date)
                                  : '',
                            ),
                            trailing: Text(
                              _attendanceStatusLabel(status),
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// Agrupa por materia conservando el orden de aparición — la lista ya
  /// viene ordenada por fecha descendente desde el RPC, así que la primera
  /// materia que aparece es la de la clase más reciente.
  Map<String, List<Map<String, dynamic>>> _groupBySubject(
    List<Map<String, dynamic>> rows,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final subject = r['subject']?.toString() ?? 'General';
      map.putIfAbsent(subject, () => []).add(r);
    }
    return map;
  }

  Widget _sectionLabel(BuildContext context, String text, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ],
  );

  Widget _buildTaskTile(Map<String, dynamic> row) {
    final estado = _estadoDe(row);
    final (color, label) = _estadoInfo(estado);
    final dueDate = DateTime.fromMillisecondsSinceEpoch(
      (row['due_date'] as num).toInt(),
    );
    final grade = row['grade']?.toString();
    final comment = row['teacher_comment']?.toString();
    final isOfficial = row['is_official'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isOfficial) ...[
                  const Icon(
                    Icons.verified_outlined,
                    size: 14,
                    color: AppColors.accentTeal,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    row['title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${row['subject']} · ${DateFormat('d MMM yyyy', 'es').format(dueDate)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            if (grade != null && grade.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Nota: $grade',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                '"$comment"',
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
