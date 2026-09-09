import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/attendance_service.dart';

/// Mi propia asistencia, de solo lectura: el docente es quien marca (ver
/// [AttendanceScreen] en admin/), esta pantalla solo espeja lo ya marcado —
/// una tabla compacta con el % de asistencia por asignatura. Tocar una fila
/// abre el detalle clase por clase.
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

  /// Mismo criterio que `get_career_attendance_summary` del lado docente:
  /// presente o tarde cuentan como asistida, sobre el total de clases
  /// marcadas.
  double _rateOf(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return 0;
    final asistidas = rows
        .where((r) => const {'presente', 'tarde'}.contains(r['status']))
        .length;
    return 100 * asistidas / rows.length;
  }

  Color _rateColor(double rate) {
    if (rate < 70) return AppColors.error;
    if (rate < 85) return Colors.orange;
    return AppColors.success;
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

    final porAsignatura = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final subject = r['subject']?.toString() ?? '';
      porAsignatura.putIfAbsent(subject, () => []).add(r);
    }
    final asignaturas = porAsignatura.keys.toList()..sort();
    final rateGeneral = _rateOf(rows);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: _rateColor(rateGeneral).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _rateColor(rateGeneral).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Asistencia general',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${rateGeneral.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _rateColor(rateGeneral),
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
                  DataColumn(label: Text('Clases')),
                  DataColumn(label: Text('Asistencia')),
                ],
                rows: asignaturas.map((s) {
                  final propias = porAsignatura[s]!;
                  final rate = _rateOf(propias);
                  return DataRow(
                    onSelectChanged: (_) =>
                        _showSubjectAttendance(context, s, propias),
                    cells: [
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(Text('${propias.length}')),
                      DataCell(
                        Text(
                          '${rate.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _rateColor(rate),
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
            'Toca una asignatura para ver el detalle de cada clase.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showSubjectAttendance(
    BuildContext context,
    String subject,
    List<Map<String, dynamic>> rows,
  ) {
    final ordenadas = [...rows]
      ..sort((a, b) {
        final da = DateTime.tryParse(a['class_date']?.toString() ?? '');
        final db = DateTime.tryParse(b['class_date']?.toString() ?? '');
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });
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
            for (final r in ordenadas)
              Builder(
                builder: (context) {
                  final status = r['status']?.toString() ?? 'sin_marcar';
                  final color = _statusColor(status);
                  final date = DateTime.tryParse(
                    r['class_date']?.toString() ?? '',
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.circle, size: 12, color: color),
                      title: Text(
                        date != null
                            ? DateFormat('EEEE d MMM', 'es').format(date)
                            : '',
                      ),
                      trailing: Text(
                        _statusLabel(status),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
