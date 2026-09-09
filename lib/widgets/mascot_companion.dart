import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../providers/theme_provider.dart';
import '../services/career_service.dart';
import 'mascot_widget.dart';

/// Compañero flotante en la pantalla principal.
/// - `sad` si hay tareas vencidas ahora mismo (se puede tocar para ver un
///   consejo puntual, calculado con los datos reales, no genérico).
/// - `content` unos segundos cada vez que entregas una tarea más.
/// - `bored` en cualquier otro momento (estado por defecto).
class MascotCompanion extends StatefulWidget {
  const MascotCompanion({super.key});

  @override
  State<MascotCompanion> createState() => _MascotCompanionState();
}

class _MascotCompanionState extends State<MascotCompanion> {
  int? _lastDeliveredCount;
  bool _celebrating = false;
  Timer? _celebrationTimer;

  @override
  void dispose() {
    _celebrationTimer?.cancel();
    super.dispose();
  }

  void _onDeliveredCountChanged(int count) {
    if (_lastDeliveredCount != null && count > _lastDeliveredCount!) {
      _celebrationTimer?.cancel();
      setState(() => _celebrating = true);
      _celebrationTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _celebrating = false);
      });
    }
    _lastDeliveredCount = count;
  }

  /// Consejo de una línea, con datos reales — no genérico ni de IA, misma
  /// filosofía que el panel de riesgo del docente ("regla simple").
  String _tipFor(List<Task> overdue) {
    if (overdue.length == 1) {
      return 'Tienes 1 tarea atrasada: "${overdue.first.title}". '
          'Organiza un rato hoy para ponerte al día.';
    }
    final oldest = overdue.reduce(
      (a, b) => a.dueDate.isBefore(b.dueDate) ? a : b,
    );
    return 'Tienes ${overdue.length} tareas atrasadas. Empieza por '
        '"${oldest.title}", es la más antigua.';
  }

  void _showTip(BuildContext context, List<Task> overdue) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Un consejo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(_tipFor(overdue), style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mascot = context.watch<ThemeProvider>().mascot;
    if (!MascotWidget.isEnabled(mascot)) return const SizedBox.shrink();

    // Reacciona a "tus tareas atrasadas" — un docente en su carrera activa
    // no tiene ninguna que le corresponda, así que directamente no aparece.
    final career = CareerService().getSelectedCareer();
    if (career != null && CareerService().isDocente(career.id)) {
      return const SizedBox.shrink();
    }

    final appState = context.watch<AppState>();
    final deliveredCount = appState.deliveredTasks.length;
    final overdue = appState.overdueTasks;
    final hasOverdue = overdue.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onDeliveredCountChanged(deliveredCount);
    });

    final state = _celebrating
        ? MascotState.content
        : (hasOverdue ? MascotState.sad : MascotState.bored);

    final mascotWidget = MascotWidget(option: mascot, state: state, size: 64);

    if (!hasOverdue) return IgnorePointer(child: mascotWidget);

    return GestureDetector(
      onTap: () => _showTip(context, overdue),
      child: mascotWidget,
    );
  }
}
