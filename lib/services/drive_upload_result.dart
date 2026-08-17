/// Lo que devolvió Drive al recibir el cuerpo del archivo.
///
/// Vive aparte para que las dos implementaciones de `putUploadBody`
/// (`drive_upload_stub.dart` y `drive_upload_web.dart`) compartan el tipo sin
/// que ninguna tenga que importar a la otra.
class DrivePutResponse {
  final int statusCode;
  final String body;

  const DrivePutResponse({required this.statusCode, required this.body});
}
