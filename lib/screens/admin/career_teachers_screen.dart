import 'package:flutter/material.dart';
import '../../colors.dart';
import '../../models/career_model.dart';
import '../../services/admin_auth_service.dart';

/// Quién dicta qué en una carrera, agrupado por docente — para no tener que
/// ir miembro por miembro a averiguarlo.
class CareerTeachersScreen extends StatefulWidget {
  final Career career;
  const CareerTeachersScreen({super.key, required this.career});

  @override
  State<CareerTeachersScreen> createState() => _CareerTeachersScreenState();
}

class _CareerTeachersScreenState extends State<CareerTeachersScreen> {
  List<TeachingAssignment>? _assignments;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await AdminAuthService.teachingAssignments(widget.career.id);
      if (mounted) setState(() => _assignments = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Map<String, List<TeachingAssignment>> _groupByTeacher(List<TeachingAssignment> rows) {
    final grouped = <String, List<TeachingAssignment>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.teacherLabel, () => []).add(row);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Docentes — ${widget.career.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Actualizar'),
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
          child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
        ),
      );
    }
    final rows = _assignments;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía nadie marcó qué asignaturas dicta en esta carrera.\n'
            'Se elige desde Configuración → Mis asignaturas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }
    final grouped = _groupByTeacher(rows);
    final teachers = grouped.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: teachers.length,
        itemBuilder: (context, i) {
          final teacher = teachers[i];
          final subjects = grouped[teacher]!;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school_outlined, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(teacher, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: subjects
                        .map((a) => Chip(
                              label: Text(a.subject, style: const TextStyle(fontSize: 12)),
                              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
                              side: BorderSide.none,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
