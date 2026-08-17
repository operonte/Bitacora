import 'dart:typed_data';

import 'picker_stub.dart'
    if (dart.library.html) 'picker_web.dart' as impl;

/// Un archivo elegido por el usuario, sin su contenido completo en memoria.
///
/// En móvil y escritorio solo se guarda [path]: pedirle a Android el archivo
/// entero como un arreglo de bytes es lo que cerraba la app al subir un video
/// de 250 MB — el sistema le pone un techo de memoria a cada app, muy por
/// debajo de la RAM del equipo. El contenido se lee del disco recién al
/// subirlo, de a poco.
///
/// En web no hay techo por pestaña y el navegador ya entrega el archivo en
/// memoria, así que ahí [bytes] viene lleno y [path] es `null`.
class PickedFileData {
  final String name;
  final int size;
  final String extension;

  /// Ruta en disco. `null` en web.
  final String? path;

  /// Contenido completo. Solo en web; `null` en móvil y escritorio.
  final Uint8List? bytes;

  /// Los primeros kilobytes del archivo.
  ///
  /// Alcanza para la validación de seguridad, que solo mira la cabecera
  /// (`FileSecurityValidator.validateFile`).
  final Uint8List head;

  PickedFileData({
    required this.name,
    required this.size,
    required this.extension,
    required this.head,
    this.path,
    this.bytes,
  });
}

class CustomFilePicker {
  /// Cuántos bytes del principio se leen para validar la cabecera.
  static const int headBytes = 4096;

  static Future<PickedFileData?> pickFile() async {
    return await impl.pickFilePlatform();
  }

  /// Borra las copias temporales que deja el selector.
  ///
  /// En Android el archivo elegido se copia a la caché de la app antes de
  /// entregarlo, así que un video de 250 MB queda ocupando disco hasta que
  /// alguien lo limpie. En web no hace nada.
  static Future<void> clearTemporaryFiles() => impl.clearTemporaryFilesPlatform();
}
