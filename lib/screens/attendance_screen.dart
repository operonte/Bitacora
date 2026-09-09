import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/attendance_service.dart';

/// Asistencia por clase, para el docente: elegir asignatura y fecha, y
/// marcar a cada alumno con un toque. Guarda apenas se toca — no hay botón
/// "Guardar" porque cada cambio ya es la fuente de verdad para esa fila.
class AttendanceScreen extends StatefulWidget {
  final Career career;
  const AttendanceScreen({super.key, required this.career});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _service = AttendanceService();
  String? _subject;
  DateTime _classDate = DateTime.now();
  List<Map<String, dynamic>>? _roster;
  String? _error;
  bool _bulkMarking = false;

  List<String> get _subjects =>
      widget.career.predefinedSubjects.map((s) => s.name).toSet().toList()
        ..sort();

  @override
  void initState() {
    super.initState();
    if (_subjects.isNotEmpty) _subject = _subjects.first;
    _load();
  }

  Future<void> _load() async {
    if (_subject == null) return;
    setState(() {
      _error = null;
      _roster = null;
    });
    try {
      final roster = await _service.getRoster(
        widget.career.id,
        _subject!,
        _classDate,
      );
      if (mounted) setState(() => _roster = roster);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _classDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _classDate = picked);
      await _load();
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
        return 'Sin marcar';
    }
  }

  Future<void> _cycleStatus(int index) async {
    final row = _roster![index];
    final current = row['status'] as String? ?? 'sin_marcar';
    const options = AttendanceService.statuses;
    final currentIdx = options.indexOf(current);
    final next = options[(currentIdx + 1) % options.length];

    setState(() {
      row['status'] = next;
      row['pending'] = true;
    });

    final confirmed = await _service.setStatus(
      widget.career.id,
      _subject!,
      _classDate,
      row['user_id'].toString(),
      next,
    );

    if (!mounted) return;
    setState(() => row['pending'] = !confirmed);
    // Sin conexión no es un error acá: queda guardado en el teléfono y se
    // sincroniza solo la próxima vez que se abra esta clase con señal.
    if (!confirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión — guardado en el teléfono, se sincroniza solo',
          ),
        ),
      );
    }
  }

  /// Marca "presente" solo a quien sigue sin marcar — no pisa lo que el
  /// docente ya haya tocado a mano (tarde/ausente/justificado). Es lo que
  /// ahorra tiempo de verdad: en un curso de 30, la mayoría llega y ya está,
  /// y solo hace falta tocar a los que faltan o llegan tarde.
  ///
  /// Una fila a la vez, no en paralelo: [AttendanceService.setStatus] lee y
  /// reescribe la misma entrada de Hive por clase, y dos escrituras a la vez
  /// se pisarían entre sí.
  Future<void> _markRestPresent() async {
    final pendientes =
        _roster
            ?.where(
              (r) => (r['status'] as String? ?? 'sin_marcar') == 'sin_marcar',
            )
            .toList() ??
        [];
    if (pendientes.isEmpty || _bulkMarking) return;

    setState(() => _bulkMarking = true);
    var sinConexion = false;
    for (final row in pendientes) {
      setState(() {
        row['status'] = 'presente';
        row['pending'] = true;
      });
      final confirmed = await _service.setStatus(
        widget.career.id,
        _subject!,
        _classDate,
        row['user_id'].toString(),
        'presente',
      );
      if (!mounted) return;
      setState(() => row['pending'] = !confirmed);
      if (!confirmed) sinConexion = true;
    }
    if (!mounted) return;
    setState(() => _bulkMarking = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sinConexion
              ? '${pendientes.length} marcados presentes — algunos sin conexión, se sincronizan solos'
              : '${pendientes.length} marcados presentes',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asistencia — ${widget.career.name}'),
        actions: [
          if (_bulkMarking)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_roster?.any(
                (r) => (r['status'] as String? ?? 'sin_marcar') == 'sin_marcar',
              ) ??
              false)
            IconButton(
              icon: const Icon(Icons.done_all),
              onPressed: _markRestPresent,
              tooltip: 'Marcar el resto presente',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _subject,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Asignatura',
                      border: OutlineInputBorder(),
                    ),
                    items: _subjects
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => _subject = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    '${_classDate.day.toString().padLeft(2, '0')}/${_classDate.month.toString().padLeft(2, '0')}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_subjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Esta carrera todavía no tiene asignaturas cargadas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
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
    final roster = _roster;
    if (roster == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (roster.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      const Color(0xFF48CAE4).withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.groups_outlined,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Nadie está inscrito en esta carrera todavía',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        itemCount: roster.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final row = roster[i];
          final displayName = (row['display_name'] as String?)?.trim();
          final name = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : (row['email'] as String? ?? 'Sin nombre');
          final status = row['status'] as String? ?? 'sin_marcar';
          final pending = row['pending'] == true;
          final color = _statusColor(status);

          return Material(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _cycleStatus(i),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 5,
                      height: 52,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(
                        name.characters.first.toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (pending) ...[
                            Icon(Icons.sync, size: 12, color: color),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _statusLabel(status),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
