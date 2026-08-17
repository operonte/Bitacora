import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'drive_upload_result.dart';

/// Manda el archivo a la sesión de subida de Drive leyéndolo del disco.
///
/// Es una única petición PUT, no una subida por trozos: la API de Drive acepta
/// el archivo completo en un solo request y ahí solo exige `Content-Length`.
/// Lo que cambia respecto de mandar un `Uint8List` es de dónde salen los
/// bytes — de un `Stream` del archivo, no de un arreglo en memoria.
///
/// `IOClient` termina haciendo `stream.pipe(ioRequest)`, que respeta
/// contrapresión: el disco no se adelanta al socket y la memoria se queda en
/// el búfer de red, sin importar si el archivo pesa 10 MB o 2 GB. Es la razón
/// de que subir un video grande deje de cerrar la app en Android.
Future<DrivePutResponse> putUploadBody(
  Uri sessionUri, {
  required String contentType,
  required int size,
  String? path,
  Uint8List? bytes,
  void Function(int sent)? onProgress,
}) async {
  final client = http.Client();
  try {
    final request = _StreamedBodyRequest(
      sessionUri,
      body: () {
        if (path != null) return File(path).openRead();
        if (bytes != null) return Stream<List<int>>.value(bytes);
        throw ArgumentError('Hace falta path o bytes para subir el archivo.');
      },
      onProgress: onProgress,
    )
      ..headers['Content-Type'] = contentType
      ..contentLength = size;

    final response = await client.send(request);
    final body = await response.stream.bytesToString();
    return DrivePutResponse(statusCode: response.statusCode, body: body);
  } finally {
    client.close();
  }
}

/// Petición cuyo cuerpo se produce recién cuando el cliente lo pide.
class _StreamedBodyRequest extends http.BaseRequest {
  final Stream<List<int>> Function() body;
  final void Function(int sent)? onProgress;

  _StreamedBodyRequest(Uri url, {required this.body, this.onProgress})
      : super('PUT', url);

  @override
  http.ByteStream finalize() {
    super.finalize();
    var sent = 0;
    final counted = body().map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent);
      return chunk;
    });
    return http.ByteStream(counted);
  }
}
