import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bitacora/services/drive_upload_stub.dart';
import 'package:flutter_test/flutter_test.dart';

/// Estos tests levantan un servidor local que hace de Google Drive y
/// comprueban lo único que de verdad cambió al arreglar el cierre en Android:
/// que el archivo se mande leyéndolo del disco, entero y sin corromperse.
void main() {
  late HttpServer server;
  late Uri uri;
  late List<int> received;
  late Map<String, String> receivedHeaders;

  setUp(() async {
    received = [];
    receivedHeaders = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://127.0.0.1:${server.port}/upload');
    server.listen((request) async {
      request.headers.forEach((name, values) {
        receivedHeaders[name.toLowerCase()] = values.join(',');
      });
      await for (final chunk in request) {
        received.addAll(chunk);
      }
      request.response
        ..statusCode = 200
        ..write(jsonEncode({'id': 'archivo-123'}));
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// Un archivo con contenido variable, para que una subida truncada o con los
  /// bloques desordenados no pase igual el test.
  File escribirArchivo(int bytes) {
    final dir = Directory.systemTemp.createTempSync('bitacora_upload_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/video.mp4');
    file.writeAsBytesSync(
      Uint8List.fromList(List.generate(bytes, (i) => (i * 31 + 7) % 256)),
    );
    return file;
  }

  test('manda el archivo completo y sin alterar leyéndolo del disco', () async {
    final file = escribirArchivo(3 * 1024 * 1024); // 3 MB
    final esperado = file.readAsBytesSync();

    final response = await putUploadBody(
      uri,
      contentType: 'video/mp4',
      size: esperado.length,
      path: file.path,
    );

    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['id'], 'archivo-123');
    expect(received.length, esperado.length);
    expect(received, orderedEquals(esperado));
  });

  test('declara Content-Length y Content-Type, que es lo que Drive exige', () async {
    final file = escribirArchivo(64 * 1024);

    await putUploadBody(
      uri,
      contentType: 'video/mp4',
      size: file.lengthSync(),
      path: file.path,
    );

    expect(receivedHeaders['content-length'], '${file.lengthSync()}');
    expect(receivedHeaders['content-type'], 'video/mp4');
  });

  test('informa el avance hasta llegar al total', () async {
    final file = escribirArchivo(1024 * 1024);
    final avances = <int>[];

    await putUploadBody(
      uri,
      contentType: 'video/mp4',
      size: file.lengthSync(),
      path: file.path,
      onProgress: avances.add,
    );

    expect(avances, isNotEmpty);
    expect(avances.last, file.lengthSync());
    // Nunca hacia atrás: el porcentaje de la pantalla se calcula con esto.
    for (var i = 1; i < avances.length; i++) {
      expect(avances[i], greaterThanOrEqualTo(avances[i - 1]));
    }
  });

  test('acepta bytes en memoria, que es el camino de web', () async {
    final contenido = Uint8List.fromList(List.generate(2048, (i) => i % 256));

    final response = await putUploadBody(
      uri,
      contentType: 'application/pdf',
      size: contenido.length,
      bytes: contenido,
    );

    expect(response.statusCode, 200);
    expect(received, orderedEquals(contenido));
  });

  test('sin path ni bytes falla en vez de subir un archivo vacío', () async {
    expect(
      () => putUploadBody(uri, contentType: 'video/mp4', size: 10),
      throwsA(isA<ArgumentError>()),
    );
  });
}
