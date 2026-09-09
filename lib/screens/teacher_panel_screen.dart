import 'dart:async';

import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/supabase_db_service.dart';
import 'student_profile_screen.dart';

/// Cada cuánto se refresca solo mientras la pantalla está abierta. No es
/// Realtime de verdad (task_progress y attendance no dejan al docente
/// suscribirse por RLS más allá del RPC), pero cubre lo que se pidió: que
/// el docente no tenga que tocar "actualizar" para ver los números al día.
const _autoRefreshInterval = Duration(seconds: 25);

/// Quién se está quedando atrás en la carrera, de un vistazo: tareas
/// oficiales vencidas sin entregar + porcentaje de asistencia. Una regla
/// simple sobre datos que la app ya junta, no un modelo de IA — es lo que la
/// investigación dice que sirve para un grupo chico sin infraestructura de
/// datos detrás.
class TeacherPanelScreen extends StatefulWidget {
  final Career career;
  const TeacherPanelScreen({super.key, required this.career});

  @override
  State<TeacherPanelScreen> createState() => _TeacherPanelScreenState();
}

class _TeacherPanelScreenState extends State<TeacherPanelScreen> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefresh = Timer.periodic(
      _autoRefreshInterval,
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  /// [silent] no muestra el spinner de carga ni borra lo que ya había en
  /// pantalla: es el refresco automático de fondo, no debe parpadear ni
  /// tapar los números con un error de fondo si justo esa vuelta falla.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _error = null;
        _rows = null;
      });
    }
    try {
      final rows = await SupabaseDbService().getStudentRisk(widget.career.id);
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _error = e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Color _attendanceColor(num? rate) {
    if (rate == null) return AppColors.textSecondary;
    if (rate < 70) return AppColors.error;
    if (rate < 85) return Colors.orange;
    return AppColors.success;
  }

  Color _missedColor(int missed) {
    if (missed >= 2) return AppColors.error;
    if (missed == 1) return Colors.orange;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Panel de riesgo — ${widget.career.name}'),
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
                      AppColors.warning.withValues(alpha: 0.15),
                      AppColors.primary.withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.insights_outlined,
                  size: 40,
                  color: AppColors.warning,
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
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final row = rows[i];
          final displayName = (row['display_name'] as String?)?.trim();
          final name = (displayName != null && displayName.isNotEmpty)
              ? displayName
              : (row['email'] as String? ?? 'Sin nombre');
          final missed = (row['missed_tasks'] as num?)?.toInt() ?? 0;
          final rate = row['attendance_rate'] as num?;
          final marked = (row['attendance_marked'] as num?)?.toInt() ?? 0;

          final severity = (missed >= 2 || (rate != null && rate < 70))
              ? AppColors.error
              : (missed == 1 || (rate != null && rate < 85))
              ? Colors.orange
              : AppColors.success;

          final userId = row['user_id']?.toString();

          return Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: InkWell(
              onTap: userId == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentProfileScreen(
                          career: widget.career,
                          studentId: userId,
                          studentName: name,
                        ),
                      ),
                    ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 5, color: severity),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  Icons.assignment_late_outlined,
                                  size: 15,
                                  color: _missedColor(missed),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  missed == 0
                                      ? 'Sin tareas oficiales atrasadas'
                                      : '$missed tarea${missed == 1 ? '' : 's'} oficial${missed == 1 ? '' : 'es'} atrasada${missed == 1 ? '' : 's'}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: _missedColor(missed),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (marked == 0)
                              const Text(
                                'Sin asistencia registrada todavía',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textSecondary,
                                ),
                              )
                            else ...[
                              Row(
                                children: [
                                  Icon(
                                    Icons.checklist_rtl,
                                    size: 15,
                                    color: _attendanceColor(rate),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Asistencia: ${rate?.toStringAsFixed(0) ?? '—'}% ($marked clases)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: _attendanceColor(rate),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: ((rate ?? 0) / 100)
                                      .clamp(0, 1)
                                      .toDouble(),
                                  minHeight: 6,
                                  backgroundColor: AppColors.textSecondary
                                      .withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation(
                                    _attendanceColor(rate),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
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
