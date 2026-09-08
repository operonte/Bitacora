import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/teacher_subject_service.dart';

/// Qué asignaturas imparte el docente en esta carrera. Autoservicio: el
/// profesor elige, no un admin — es lo que después cruza con el semestre
/// del alumno para saber a quién le llega su material y su asistencia.
class TeacherSubjectsScreen extends StatefulWidget {
  final Career career;
  const TeacherSubjectsScreen({super.key, required this.career});

  @override
  State<TeacherSubjectsScreen> createState() => _TeacherSubjectsScreenState();
}

class _TeacherSubjectsScreenState extends State<TeacherSubjectsScreen> {
  Set<String>? _teaching;
  String? _error;

  List<String> get _subjects =>
      widget.career.predefinedSubjects.map((s) => s.name).toSet().toList()..sort();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final mine = await TeacherSubjectService.myTeachingSubjects(widget.career.id);
      if (mounted) setState(() => _teaching = mine.toSet());
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _toggle(String subject, bool value) async {
    setState(() {
      final updated = {..._teaching!};
      if (value) {
        updated.add(subject);
      } else {
        updated.remove(subject);
      }
      _teaching = updated;
    });
    try {
      await TeacherSubjectService.setTeaching(widget.career.id, subject, value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar: $e')),
        );
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Mis asignaturas — ${widget.career.name}')),
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
    final teaching = _teaching;
    if (teaching == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.menu_book_outlined, size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: 14),
              const Text(
                'Esta carrera todavía no tiene asignaturas cargadas',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            'Marca las que dictas. Se usa para saber a qué alumnos les llega '
            'tu material y tu asistencia.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        ..._subjects.map((s) {
          final selected = teaching.contains(s);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Material(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _toggle(s, !selected),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.textSecondary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected ? AppColors.primary : AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          s,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}
