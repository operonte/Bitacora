import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/theme_provider.dart';
import 'mascot_widget.dart';

/// Compañero flotante en la pantalla principal.
/// - `angry` si hay tareas vencidas ahora mismo.
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

  @override
  Widget build(BuildContext context) {
    final mascot = context.watch<ThemeProvider>().mascot;
    if (!MascotWidget.isEnabled(mascot)) return const SizedBox.shrink();

    final appState = context.watch<AppState>();
    final deliveredCount = appState.deliveredTasks.length;
    final hasOverdue = appState.overdueTasks.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onDeliveredCountChanged(deliveredCount);
    });

    final state = _celebrating
        ? MascotState.content
        : (hasOverdue ? MascotState.angry : MascotState.bored);

    return IgnorePointer(
      child: MascotWidget(option: mascot, state: state, size: 64),
    );
  }
}
