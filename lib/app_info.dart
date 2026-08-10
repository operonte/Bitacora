/// Datos de identidad de la app que se muestran al usuario.
///
/// [version] tiene que coincidir con `version:` de pubspec.yaml. Se duplica
/// acá a propósito: leerla del paquete real exige `package_info_plus`, y por
/// ahora no se quiere sumar una dependencia solo para un diálogo. Si algún día
/// se agrega, este archivo desaparece y la versión sale del build.
///
/// Hasta entonces: **al subir la versión en pubspec.yaml, subirla también acá.**
class AppInfo {
  const AppInfo._();

  static const String name = 'Bitácora';
  static const String version = '2.10.1';
  static const String developer = 'Operonte';

  /// Identifica la compilación concreta, no solo la versión publicada.
  ///
  /// Hizo falta el 2026-08-08: en un mismo día salieron seis APK distintos,
  /// todos diciendo "2.8.0". Cuando aparecieron archivos duplicados no hubo
  /// forma de saber qué compilación tenía instalada el teléfono ni si el
  /// código que los creaba seguía ahí, y el diagnóstico se convirtió en
  /// adivinar. Se sube a mano en cada compilación que se instale o despliegue.
  static const String build = '2026-08-10.3';

  /// "Versión 2.8.1", listo para pintar.
  static String get versionLabel => 'Versión $version';

  /// "Versión 2.8.1 · compilación 2026-08-08.9", para la pantalla de
  /// configuración: es lo que hay que preguntar cuando algo no calza.
  static String get buildLabel => '$versionLabel · compilación $build';
}
