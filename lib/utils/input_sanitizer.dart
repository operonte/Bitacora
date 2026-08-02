/// Utilidad avanzada de seguridad para sanitizar entradas de texto en formularios (OWASP A03 / A04)
class InputSanitizer {
  /// Máxima longitud permitida para campos de texto para evitar ataques de DoS por Payload Masivo
  static const int maxTitleLength = 150;
  static const int maxDescriptionLength = 3000;
  static const int maxSearchLength = 100;

  /// Sanitiza cadenas de texto eliminando etiquetas HTML/Script, caracteres nulos y recortando la longitud
  static String sanitizeText(String input, {int maxLength = maxDescriptionLength}) {
    if (input.isEmpty) return input;

    var sanitized = input;

    // 1. Eliminar caracteres nulos y caracteres de control invisibles
    sanitized = sanitized.replaceAll(RegExp(r'[\u0000\u200B-\u200D\uFEFF]'), '');

    // 2. Eliminar etiquetas <script> y su contenido
    sanitized = sanitized.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?<\/script>', caseSensitive: false),
      '',
    );

    // 3. Eliminar eventos inline de HTML (ej. onerror=, onload=, onclick=)
    sanitized = sanitized.replaceAll(
      RegExp(r'on[a-zA-Z]+\s*=', caseSensitive: false),
      '',
    );

    // 4. Eliminar cualquier otra etiqueta HTML (ej. <iframe>, <img>, <style>, <link>)
    sanitized = sanitized.replaceAll(
      RegExp(r'<[^>]*>', caseSensitive: false),
      '',
    );

    // 5. Truncar si excede la longitud máxima segura para prevenir desbordamientos o DoS
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    return sanitized.trim();
  }

  /// Sanitiza términos de búsqueda escapando comodines de SQL (% y _)
  static String sanitizeSearchQuery(String query) {
    if (query.isEmpty) return query;
    var sanitized = sanitizeText(query, maxLength: maxSearchLength);
    // Escapar comodines SQL para evitar consultas abusivas con LIKE %%%
    return sanitized.replaceAll('%', r'\%').replaceAll('_', r'\_');
  }

  /// Limpia correos electrónicos descartando caracteres inválidos
  static String sanitizeEmail(String email) {
    var clean = email.trim().toLowerCase();
    clean = clean.replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F]'), '');
    return clean;
  }
}
