import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/supabase_db_service.dart';

/// Resumen de asistencia de TODA la carrera, asignatura por asignatura — no
/// solo la que imparte quien mira. Complementa a [AttendanceScreen] (que
/// marca la asistencia de una clase puntual): acá se ve el % acumulado por
/// alumno y materia, para dar feedback cruzado con otros docentes.
class CareerAttendanceScreen extends StatefulWidget {
  final Career career;
  const CareerAttendanceScreen({super.key, required this.career});

  @override
  State<CareerAttendanceScreen> createState() =>
      _CareerAttendanceScreenState();
}

class _CareerAttendanceScreenState extends State<CareerAttendanceScreen> {
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
      final rows = await SupabaseDbService().getCareerAttendanceSummary(
        widget.career.id,
      );
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

  Color _rateColor(num? rate) {
    if (rate == null) return AppColors.textSecondary;
    if (rate < 70) return AppColors.error;
    if (rate < 85) return Colors.orange;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asistencia — ${widget.career.name}'),
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
            'Todavía no hay asistencia registrada en esta carrera.',
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
            headingRowHeight: 36,
            dataRowMinHeight: 34,
            dataRowMaxHeight: 34,
            columnSpacing: 20,
            horizontalMargin: 12,
            headingTextStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
            dataTextStyle: const TextStyle(fontSize: 12.5),
            columns: const [
              DataColumn(label: Text('Alumno')),
              DataColumn(label: Text('Asignatura')),
              DataColumn(label: Text('Asistencia')),
              DataColumn(label: Text('Clases')),
            ],
            rows: rows.map((r) {
              final rate = r['attendance_rate'] as num?;
              final marked = (r['marked'] as num?)?.toInt() ?? 0;
              return DataRow(
                cells: [
                  DataCell(Text(_nameOf(r))),
                  DataCell(Text((r['subject'] as String?) ?? '')),
                  DataCell(
                    Text(
                      rate == null ? '—' : '${rate.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _rateColor(rate),
                      ),
                    ),
                  ),
                  DataCell(Text('$marked')),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
