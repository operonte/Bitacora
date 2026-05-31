import 'package:flutter/material.dart';
import 'task_model.dart';

class AppColors {
  // Paleta principal — azul índigo profundo
  static const Color primary = Color(0xFF3D5AFE);
  static const Color primaryDark = Color(0xFF0031CA);
  static const Color primaryLight = Color(0xFF8187FF);
  static const Color accent = Color(0xFF00BCD4);
  static const Color secondary = Color(0xFF1A237E);

  // Fondos modo claro
  static const Color background = Color(0xFFF4F6FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);

  // Textos
  static const Color onSurface = Color(0xFF1C1F26);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFFB0B7C3);

  // Semánticos
  static const Color error = Color(0xFFE53935);
  static const Color success = Color(0xFF43A047);
  static const Color warning = Color(0xFFFB8C00);

  // Urgencia de tareas
  static const Color celeste = Color(0xFF29B6F6);
  static const Color verde = Color(0xFF66BB6A);
  static const Color amarillo = Color(0xFFFFCA28);
  static const Color naranjo = Color(0xFFFF7043);
  static const Color rojo = Color(0xFFEF5350);
  static const Color gris = Color(0xFF90A4AE);

  // Modo oscuro
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF161B22);
  static const Color darkCard = Color(0xFF1C2128);
  static const Color darkOnSurface = Color(0xFFE6EDF3);
  static const Color darkTextSecondary = Color(0xFF8B949E);
  static const Color darkAppBar = Color(0xFF0D1117);
}

class TaskColorHelper {
  static Color getUrgencyColor(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return AppColors.celeste;
      case TaskUrgency.medium:
        return AppColors.verde;
      case TaskUrgency.high:
        return AppColors.amarillo;
      case TaskUrgency.urgent:
        return AppColors.naranjo;
      case TaskUrgency.overdue:
        return AppColors.rojo;
      case TaskUrgency.completed:
        return AppColors.gris;
    }
  }

  static Color getUrgencyBg(TaskUrgency urgency) {
    return getUrgencyColor(urgency).withValues(alpha: 0.10);
  }

  static IconData getUrgencyIcon(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return Icons.schedule;
      case TaskUrgency.medium:
        return Icons.timelapse;
      case TaskUrgency.high:
        return Icons.warning_amber_rounded;
      case TaskUrgency.urgent:
        return Icons.priority_high_rounded;
      case TaskUrgency.overdue:
        return Icons.error_outline_rounded;
      case TaskUrgency.completed:
        return Icons.check_circle_outline;
    }
  }

  static String getUrgencyText(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return 'Con tiempo';
      case TaskUrgency.medium:
        return 'Moderada';
      case TaskUrgency.high:
        return 'Alta';
      case TaskUrgency.urgent:
        return '¡Urgente!';
      case TaskUrgency.overdue:
        return 'Vencida';
      case TaskUrgency.completed:
        return 'Entregada';
    }
  }
}

// Extensión útil para obtener colores según tema
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bgColor => isDark ? AppColors.darkBackground : AppColors.background;
  Color get surfaceColor => isDark ? AppColors.darkSurface : AppColors.surface;
  Color get cardColor => isDark ? AppColors.darkCard : AppColors.cardBg;
  Color get textColor => isDark ? AppColors.darkOnSurface : AppColors.onSurface;
  Color get textSecondaryColor => isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
}
