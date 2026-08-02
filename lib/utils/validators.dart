/// Utilidades de validación de formularios
class Validators {
  /// Valida que un campo de texto no esté vacío
  static String? required(String? value, [String fieldName = 'Este campo']) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName es obligatorio';
    }
    return null;
  }

  /// Valida longitud mínima
  static String? minLength(String? value, int min, [String fieldName = 'Este campo']) {
    if (value != null && value.trim().length < min) {
      return '$fieldName debe tener al menos $min caracteres';
    }
    return null;
  }

  /// Valida longitud máxima
  static String? maxLength(String? value, int max, [String fieldName = 'Este campo']) {
    if (value != null && value.trim().length > max) {
      return '$fieldName no puede exceder $max caracteres';
    }
    return null;
  }

  /// Valida rango de longitud
  static String? lengthRange(String? value, int min, int max, [String fieldName = 'Este campo']) {
    final length = value?.trim().length ?? 0;
    if (length < min) {
      return '$fieldName debe tener al menos $min caracteres';
    }
    if (length > max) {
      return '$fieldName no puede exceder $max caracteres';
    }
    return null;
  }

  /// Valida que la fecha no sea pasada
  static String? futureDate(DateTime? date, [String fieldName = 'La fecha']) {
    if (date == null) {
      return '$fieldName es obligatoria';
    }
    if (date.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
      return '$fieldName no puede ser pasada';
    }
    return null;
  }

  /// Valida que un campo sea solo letras y espacios
  static String? lettersOnly(String? value, [String fieldName = 'Este campo']) {
    if (value != null && value.trim().isNotEmpty) {
      if (!RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]+$').hasMatch(value.trim())) {
        return '$fieldName solo puede contener letras';
      }
    }
    return null;
  }

  /// Valida formato de email
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El email es obligatorio';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) {
      return 'Ingresa un email válido';
    }
    return null;
  }

  /// Validador compuesto para campos requeridos con longitud mínima
  static String? requiredWithMinLength(String? value, int min, [String fieldName = 'Este campo']) {
    final requiredResult = required(value, fieldName);
    if (requiredResult != null) return requiredResult;
    return minLength(value, min, fieldName);
  }

  /// Validador compuesto para campos requeridos con rango de longitud
  static String? requiredWithLengthRange(String? value, int min, int max, [String fieldName = 'Este campo']) {
    final requiredResult = required(value, fieldName);
    if (requiredResult != null) return requiredResult;
    return lengthRange(value, min, max, fieldName);
  }
}
