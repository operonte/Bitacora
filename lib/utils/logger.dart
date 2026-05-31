import 'package:flutter/foundation.dart';

/// Niveles de log para el sistema de logging.
enum LogLevel { debug, info, warning, error }

/// Servicio de logging estructurado para la aplicación.
///
/// Proporciona un sistema centralizado para registrar eventos, errores
/// y información de debugging con diferentes niveles de severidad.
class Logger {
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  /// Habilita o deshabilita los logs en producción.
  static bool _enabled = kDebugMode;

  /// Establece si los logs están habilitados.
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Registra un mensaje de nivel DEBUG.
  /// Se usa para información detallada de debugging.
  static void debug(String message, {String? tag, dynamic error}) {
    _log(LogLevel.debug, message, tag: tag, error: error);
  }

  /// Registra un mensaje de nivel INFO.
  /// Se usa para información general sobre el funcionamiento.
  static void info(String message, {String? tag, dynamic error}) {
    _log(LogLevel.info, message, tag: tag, error: error);
  }

  /// Registra un mensaje de nivel WARNING.
  /// Se usa para situaciones potencialmente problemáticas.
  static void warning(String message, {String? tag, dynamic error}) {
    _log(LogLevel.warning, message, tag: tag, error: error);
  }

  /// Registra un mensaje de nivel ERROR.
  /// Se usa para errores que no detienen la aplicación.
  static void error(String message, {String? tag, dynamic error}) {
    _log(LogLevel.error, message, tag: tag, error: error);
  }

  /// Implementación interna del logging.
  static void _log(
    LogLevel level,
    String message, {
    String? tag,
    dynamic error,
  }) {
    if (!_enabled) return;

    final timestamp = DateTime.now().toIso8601String();
    final tagStr = tag != null ? '[$tag]' : '[Bitacora]';
    final levelStr = _getLevelString(level);
    final emoji = _getLevelEmoji(level);

    // Formato: [timestamp] [tag] [level] emoji message
    final logMessage = '$timestamp $tagStr $levelStr $emoji $message';

    // En debug mode, usar debugPrint para mejor formato
    if (kDebugMode) {
      debugPrint(logMessage);
      if (error != null) {
        debugPrint('  Error: $error');
      }
    }
  }

  /// Obtiene la cadena de texto para el nivel de log.
  static String _getLevelString(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO ';
      case LogLevel.warning:
        return 'WARN ';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  /// Obtiene el emoji para el nivel de log.
  static String _getLevelEmoji(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🔍';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
    }
  }

  /// Registra el inicio de una operación asíncrona.
  static void startOperation(String operationName, {String? tag}) {
    info('▶️ Iniciando: $operationName', tag: tag);
  }

  /// Registra el éxito de una operación asíncrona.
  static void endOperation(
    String operationName, {
    String? tag,
    Duration? duration,
  }) {
    final durationStr = duration != null
        ? ' (${duration.inMilliseconds}ms)'
        : '';
    info('✅ Completado: $operationName$durationStr', tag: tag);
  }

  /// Registra el fallo de una operación asíncrona.
  static void failOperation(
    String operationName,
    dynamic error, {
    String? tag,
  }) {
    error('❌ Falló: $operationName - $error', tag: tag, error: error);
  }

  /// Registra información de una red o conexión.
  static void network(String message, {String? tag}) {
    info('🌐 $message', tag: tag);
  }

  /// Registra información de base de datos.
  static void database(String message, {String? tag}) {
    debug('🗄️ $message', tag: tag);
  }

  /// Registra información de autenticación.
  static void auth(String message, {String? tag}) {
    info('🔐 $message', tag: tag);
  }

  /// Registra información de notificaciones.
  static void notification(String message, {String? tag}) {
    debug('🔔 $message', tag: tag);
  }

  /// Registra información de sincronización.
  static void sync(String message, {String? tag}) {
    info('🔄 $message', tag: tag);
  }

  /// Registra información de caché.
  static void cache(String message, {String? tag}) {
    debug('💾 $message', tag: tag);
  }

  /// Registra información de UI.
  static void ui(String message, {String? tag}) {
    debug('🎨 $message', tag: tag);
  }
}

/// Extensión para facilitar el logging en clases.
extension LoggerExtension on Object {
  /// Obtiene el nombre de la clase para usar como tag.
  String get _className => runtimeType.toString();

  /// Log de nivel debug con el nombre de la clase como tag.
  void logDebug(String message, {dynamic error}) {
    Logger.debug(message, tag: _className, error: error);
  }

  /// Log de nivel info con el nombre de la clase como tag.
  void logInfo(String message, {dynamic error}) {
    Logger.info(message, tag: _className, error: error);
  }

  /// Log de nivel warning con el nombre de la clase como tag.
  void logWarning(String message, {dynamic error}) {
    Logger.warning(message, tag: _className, error: error);
  }

  /// Log de nivel error con el nombre de la clase como tag.
  void logError(String message, {dynamic error}) {
    Logger.error(message, tag: _className, error: error);
  }
}
