import 'package:flutter/material.dart';
import '../colors.dart';
import '../models/task_model.dart';

/// Fila horizontal de chips para filtrar una lista de tareas por materia.
/// "Todos" siempre va primero. No se muestra si hay una sola materia — no
/// hay nada que filtrar. Antes solo existía (copiado a mano) en Pendientes;
/// Vencidas y Entregadas se quedaban sin poder acotar por materia.
class SubjectFilterChips extends StatelessWidget {
  static const String all = 'Todos';

  final List<Task> tasks;
  final String selected;
  final ValueChanged<String> onSelected;

  const SubjectFilterChips({
    super.key,
    required this.tasks,
    required this.selected,
    required this.onSelected,
  });

  static bool matches(Task task, String selected) =>
      selected == all || task.subject == selected;

  @override
  Widget build(BuildContext context) {
    final subjectNames = tasks.map((t) => t.subject).toSet().toList()..sort();
    subjectNames.insert(0, all);
    if (subjectNames.length <= 1) return const SizedBox.shrink();

    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 60,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: subjectNames.length,
        itemBuilder: (context, index) {
          final subject = subjectNames[index];
          final isSelected = subject == selected;
          final dotColor = subject == all
              ? null
              : SubjectColorHelper.colorFor(subject);

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              avatar: dotColor == null
                  ? null
                  : CircleAvatar(backgroundColor: dotColor, radius: 5),
              label: Text(
                subject,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              selected: isSelected,
              onSelected: (_) => onSelected(subject),
              backgroundColor: isDark
                  ? AppColors.darkSurface
                  : Colors.grey[200],
              selectedColor: primaryColor,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? primaryColor : AppColors.borderLight,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
