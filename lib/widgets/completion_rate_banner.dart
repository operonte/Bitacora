import 'package:flutter/material.dart';
import '../colors.dart';

/// "Cumplimiento": de las tareas que ya llegaron a su fecha límite (las que
/// se entregaron más las que quedaron vencidas sin entregar), qué porcentaje
/// se entregó. No es "a tiempo" — la app no guarda cuándo se marcó cada
/// tarea como completada, así que no puede distinguir una entrega a último
/// minuto de una vencida y completada después — pero sí es una señal honesta
/// de cuánto se está quedando sin resolver.
///
/// Se esconde con pocos datos (menos de 5 tareas resueltas): un 100% o un 0%
/// de una sola tarea no dice nada y solo sería ruido para una cuenta nueva.
class CompletionRateBanner extends StatelessWidget {
  static const int minSample = 5;

  final int delivered;
  final int overdue;

  const CompletionRateBanner({
    super.key,
    required this.delivered,
    required this.overdue,
  });

  @override
  Widget build(BuildContext context) {
    final total = delivered + overdue;
    if (total < minSample) return const SizedBox.shrink();

    final rate = (delivered / total * 100).round();
    final color = rate >= 80
        ? AppColors.success
        : rate >= 50
        ? AppColors.warning
        : AppColors.rojo;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.insights_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$rate% de cumplimiento — $delivered de $total tareas entregadas',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
