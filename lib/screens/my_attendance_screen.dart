import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/attendance_service.dart';
import '../widgets/subject_group_list.dart';

/// Mi propia asistencia, de solo lectura: el docente es quien marca (ver
/// [AttendanceScreen] en admin/), esta pantalla solo espeja lo ya marcado
/// agrupado por asignatura, para que el alumno pueda revisar su registro sin
/// tener que pedírselo a nadie.
class MyAttendanceScreen extends StatefulWidget {
  final Career career;
  const MyAttendanceScreen({super.key, required this.career});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  final _service = AttendanceService();
  List<Map<String, dynamic>>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rows = await _service.getMyAttendance(widget.career.id);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Color _statusColor(String status) {
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

  String _statusLabel(String status) {
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
        title: Text('Mi asistencia — ${widget.career.name}'),
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
            'Todavía no hay asistencia marcada en esta carrera.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: SubjectGroupList<Map<String, dynamic>>(
        items: rows,
        subjectOf: (r) => r['subject']?.toString() ?? '',
        countLabelOf: (n) => n == 1 ? '1 clase' : '$n clases',
        dateOf: (r) => DateTime.tryParse(r['class_date']?.toString() ?? ''),
        dateDescending: true,
        itemBuilder: (r) {
          final status = r['status']?.toString() ?? 'sin_marcar';
          final color = _statusColor(status);
          final date = DateTime.tryParse(r['class_date']?.toString() ?? '');
          return ListTile(
            dense: true,
            leading: Icon(Icons.circle, size: 12, color: color),
            title: Text(
              date != null ? DateFormat('EEEE d MMM', 'es').format(date) : '',
            ),
            trailing: Text(
              _statusLabel(status),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          );
        },
      ),
    );
  }
}
