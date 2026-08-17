import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'drive_upload_result.dart';

/// Igual que en móvil, pero con los bytes que el navegador ya tiene cargados.
///
/// En web no existe el techo de memoria por app que tiene Android, y este es
/// el camino que ya está probado en producción, así que se deja como estaba:
/// una sola petición PUT con el archivo completo en el cuerpo.
Future<DrivePutResponse> putUploadBody(
  Uri sessionUri, {
  required String contentType,
  required int size,
  String? path,
  Uint8List? bytes,
  void Function(int sent)? onProgress,
}) async {
  if (bytes == null) {
    throw ArgumentError('En web hace falta el contenido del archivo en bytes.');
  }

  final response = await http.put(
    sessionUri,
    headers: {
      'Content-Type': contentType,
      'Content-Length': '$size',
    },
    body: bytes,
  );

  // El navegador no informa el avance de un XHR sin más, así que se avisa el
  // total recién al terminar: es eso o no mostrar nada.
  onProgress?.call(size);

  return DrivePutResponse(
    statusCode: response.statusCode,
    body: response.body,
  );
}
