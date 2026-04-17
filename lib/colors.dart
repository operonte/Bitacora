import 'package:flutter/material.dart';
import 'task_model.dart';

class AppColors {
  // Colores para urgencia de tareas
  static const Color celeste = Color(0xFF87CEEB);     // Mucho tiempo
  static const Color verde = Color(0xFF4CAF50);      // Tiempo moderado
  static const Color amarillo = Color(0xFFFFC107);   // Tiempo limitado
  static const Color naranjo = Color(0xFFFF9800);    // Urgente
  static const Color rojo = Color(0xFFF44336);        // Vencida no realizada
  static const Color gris = Color(0xFF9E9E9E);        // Completada y enviada

  // Colores de la aplicación
  static const Color primary = Color(0xFF2196F3);
  static const Color secondary = Color(0xFF1976D2);
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF212121);
  static const Color error = Color(0xFFD32F2F);

  // Colores modo oscuro
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkOnSurface = Color(0xFFFFFFFF);
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

  static String getUrgencyText(TaskUrgency urgency) {
    switch (urgency) {
      case TaskUrgency.low:
        return 'Baja urgencia';
      case TaskUrgency.medium:
        return 'Moderada';
      case TaskUrgency.high:
        return 'Alta urgencia';
      case TaskUrgency.urgent:
        return '¡Urgente!';
      case TaskUrgency.overdue:
        return 'Vencida';
      case TaskUrgency.completed:
        return 'Completada';
    }
  }
}
