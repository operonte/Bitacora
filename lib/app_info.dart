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
  static const String version = '2.8.0';
  static const String developer = 'Operonte';

  /// "Versión 2.7.1", listo para pintar.
  static String get versionLabel => 'Versión $version';
}
