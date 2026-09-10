import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../providers/theme_provider.dart';
import '../services/career_service.dart';
import 'mascot_widget.dart';

/// Compañero flotante en la pantalla principal.
/// - `content` unos segundos cada vez que entregas una tarea más.
/// - `sad` con 1 tarea atrasada, `angry` con 2 o más — mismo umbral que ya
///   usa [_tipFor] para diferenciar el consejo, no un número nuevo inventado.
/// - `bored` en cualquier otro momento (estado por defecto).
///
/// Siempre se puede tocar: cuenta, en primera persona, por qué está así —
/// no solo la cara, también el motivo, mientras haya lugar en la pantalla.
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

  /// Por qué está así, en primera persona, con datos reales — no genérico
  /// ni de IA, misma filosofía que el panel de riesgo del docente ("regla
  /// simple"). Un texto por estado, así el gesto de tocarla siempre cuenta
  /// algo, no solo cuando hay algo atrasado.
  String _fraseFor(MascotState state, List<Task> overdue) {
    switch (state) {
      case MascotState.content:
        return 'Estoy contento — acabas de entregar una tarea más.';
      case MascotState.angry:
        final oldest = overdue.reduce(
          (a, b) => a.dueDate.isBefore(b.dueDate) ? a : b,
        );
        return 'Estoy enojado: llevas ${overdue.length} tareas atrasadas. '
            'Empieza por "${oldest.title}", es la más antigua.';
      case MascotState.sad:
        return 'Me da pena que te atrases: tienes 1 tarea atrasada — '
            '"${overdue.first.title}". Organiza un rato hoy para ponerte '
            'al día.';
      case MascotState.bored:
      case MascotState.surprised:
        return 'Estoy tranquilo — no tienes tareas atrasadas por ahora.';
    }
  }

  void _showTip(BuildContext context, MascotState state, List<Task> overdue) {
    final (icon, color) = switch (state) {
      MascotState.content => (Icons.sentiment_satisfied_alt, Colors.green),
      MascotState.angry => (Icons.sentiment_very_dissatisfied, Colors.red),
      MascotState.sad => (Icons.sentiment_dissatisfied, Colors.orange),
      _ => (Icons.sentiment_neutral, Colors.blueGrey),
    };
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _fraseFor(state, overdue),
                style: const TextStyle(fontSize: 14),
              ),
            ),
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
        : (overdue.length >= 2
              ? MascotState.angry
              : (hasOverdue ? MascotState.sad : MascotState.bored));

    final mascotWidget = MascotWidget(option: mascot, state: state, size: 64);

    return GestureDetector(
      onTap: () => _showTip(context, state, overdue),
      child: mascotWidget,
    );
  }
}
