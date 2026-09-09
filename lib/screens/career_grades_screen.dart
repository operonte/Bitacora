import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/supabase_db_service.dart';

/// Todas las notas de la carrera, de cualquier asignatura — no solo la que
/// imparte quien mira. Pedido explícito: un docente se da feedback con sus
/// colegas viendo cómo le va a un alumno en otras materias, no solo la suya.
///
/// Una fila por nota, no una grilla con celdas fusionadas: si un alumno
/// tiene tres tareas calificadas en la misma materia, son tres filas.
class CareerGradesScreen extends StatefulWidget {
  final Career career;
  const CareerGradesScreen({super.key, required this.career});

  @override
  State<CareerGradesScreen> createState() => _CareerGradesScreenState();
}

class _CareerGradesScreenState extends State<CareerGradesScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _rows = null;
    });
    try {
      final rows = await SupabaseDbService().getCareerGrades(widget.career.id);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  String _nameOf(Map<String, dynamic> row) {
    final name = (row['student_name'] as String?)?.trim();
    if (name != null && name.isNotEmpty) return name;
    return (row['student_email'] as String?) ?? 'Sin nombre';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Notas — ${widget.career.name}'),
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
    final rows = _rows;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Todavía no hay notas registradas en esta carrera.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Alumno')),
              DataColumn(label: Text('Asignatura')),
              DataColumn(label: Text('Tarea')),
              DataColumn(label: Text('Nota')),
            ],
            rows: rows
                .map(
                  (r) => DataRow(
                    cells: [
                      DataCell(Text(_nameOf(r))),
                      DataCell(Text((r['subject'] as String?) ?? '')),
                      DataCell(Text((r['task_title'] as String?) ?? '')),
                      DataCell(
                        Text(
                          (r['grade'] as String?) ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}
