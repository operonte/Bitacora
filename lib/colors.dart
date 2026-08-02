import 'package:flutter/material.dart';
import 'models/task_model.dart';

enum AppColorPalette { teal, emerald, feminine }

class AppColors {
  // ── Paleta: Por defecto (Teal Académico) ───────────────────
  static const Color primaryTeal = Color(0xFF0D9488);      // Teal 600
  static const Color primaryTealLight = Color(0xFF2DD4BF); // Teal 400
  static const Color primaryTealDark = Color(0xFF115E59);  // Teal 800
  static const Color accentTeal = Color(0xFFEA580C);       // Naranjo 600 (CTA)
  static const Color containerTeal = Color(0xFFF0FDFA);    // Tinte suave teal

  // ── Paleta: Verde (Emerald Bio Pro) ───────────────────────
  static const Color primaryEmerald = Color(0xFF059669);     // Esmeralda 600
  static const Color primaryEmeraldLight = Color(0xFF34D399); // Esmeralda 400
  static const Color primaryEmeraldDark = Color(0xFF047857);  // Esmeralda 800
  static const Color accentEmerald = Color(0xFF10B981);      // Menta 500
  static const Color containerEmerald = Color(0xFFECFDF5);   // Tinte suave esmeralda

  // ── Paleta: Rosa (Malva Glam Pro) ─────────────────────────
  static const Color primaryFeminine = Color(0xFFDB2777);    // Rosa / Malva 600
  static const Color primaryFeminineLight = Color(0xFFF472B6);// Rosa 400
  static const Color primaryFeminineDark = Color(0xFFBE185D); // Rosa 800
  static const Color accentFeminine = Color(0xFFF43F5E);     // Malva/Coral 500
  static const Color containerFeminine = Color(0xFFFDF2F8);  // Tinte suave rosa

  // Getters dinámicos por paleta
  static Color getPrimary(AppColorPalette palette) {
    switch (palette) {
      case AppColorPalette.teal:
        return primaryTeal;
      case AppColorPalette.emerald:
        return primaryEmerald;
      case AppColorPalette.feminine:
        return primaryFeminine;
    }
  }

  static Color getPrimaryLight(AppColorPalette palette) {
    switch (palette) {
      case AppColorPalette.teal:
        return primaryTealLight;
      case AppColorPalette.emerald:
        return primaryEmeraldLight;
      case AppColorPalette.feminine:
        return primaryFeminineLight;
    }
  }

  static Color getPrimaryDark(AppColorPalette palette) {
    switch (palette) {
      case AppColorPalette.teal:
        return primaryTealDark;
      case AppColorPalette.emerald:
        return primaryEmeraldDark;
      case AppColorPalette.feminine:
        return primaryFeminineDark;
    }
  }

  static Color getAccent(AppColorPalette palette) {
    switch (palette) {
      case AppColorPalette.teal:
        return accentTeal;
      case AppColorPalette.emerald:
        return accentEmerald;
      case AppColorPalette.feminine:
        return accentFeminine;
    }
  }

  static Color getContainerBg(AppColorPalette palette) {
    switch (palette) {
      case AppColorPalette.teal:
        return containerTeal;
      case AppColorPalette.emerald:
        return containerEmerald;
      case AppColorPalette.feminine:
        return containerFeminine;
    }
  }

  static LinearGradient getGradient(AppColorPalette palette) {
    return LinearGradient(
      colors: [getPrimary(palette), getAccent(palette)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }

  // Paleta predeterminada estática (backward compatibility fallback)
  static const Color primary = primaryTeal;
  static const Color primaryDark = primaryTealDark;
  static const Color primaryLight = primaryTealLight;
  static const Color accent = accentTeal;
  static const Color secondary = primaryTealLight;

  // Modo claro (Warm Neutral)
  static const Color background = Color(0xFFFAFAF9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF78716C);
  static const Color textHint = Color(0xFFA8A29E);
  static const Color borderLight = Color(0xFFE7E5E4);

  // Modo oscuro (Warm Neutral Dark)
  static const Color darkBackground = Color(0xFF1C1917);
  static const Color darkSurface = Color(0xFF292524);
  static const Color darkCard = Color(0xFF292524);
  static const Color darkOnSurface = Color(0xFFFAFAF9);
  static const Color darkTextSecondary = Color(0xFFA8A29E);
  static const Color darkTextHint = Color(0xFF78716C);
  static const Color darkBorder = Color(0xFF44403C);
  static const Color darkAppBar = Color(0xFF1C1917);

  // Semánticos
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);

  // Urgencia de tareas
  static const Color celeste = Color(0xFF38BDF8);
  static const Color verde = Color(0xFF34D399);
  static const Color amarillo = Color(0xFFFBBF24);
  static const Color naranjo = Color(0xFFFB923C);
  static const Color rojo = Color(0xFFF87171);
  static const Color gris = Color(0xFF94A3B8);
}

extension ThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get textColor => isDark ? AppColors.darkOnSurface : AppColors.onSurface;
  Color get textSecondaryColor => isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get textHintColor => isDark ? AppColors.darkTextHint : AppColors.textHint;
  Color get borderColor => isDark ? AppColors.darkBorder : AppColors.borderLight;
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
    return getUrgencyColor(urgency).withValues(alpha: 0.12);
  }

  static IconData getUrgencyIcon(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return Icons.info_outline;
      case TaskUrgency.medium:
        return Icons.schedule;
      case TaskUrgency.high:
        return Icons.warning_amber_rounded;
      case TaskUrgency.urgent:
        return Icons.priority_high;
      case TaskUrgency.overdue:
        return Icons.error_outline;
      case TaskUrgency.completed:
        return Icons.check_circle_outline;
    }
  }

  static String getUrgencyText(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return 'Baja';
      case TaskUrgency.medium:
        return 'Media';
      case TaskUrgency.high:
        return 'Alta';
      case TaskUrgency.urgent:
        return 'Urgente';
      case TaskUrgency.overdue:
        return 'Vencida';
      case TaskUrgency.completed:
        return 'Completada';
    }
  }
}
