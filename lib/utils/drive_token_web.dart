// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_interop';

/// Declaración del tipo de función callback para JS
extension type _DriveTokenCallback._(JSFunction _) implements JSFunction {
  external factory _DriveTokenCallback(JSString? token);
}

@JS('requestGoogleDriveToken')
external void _requestGoogleDriveToken(
  JSString clientId,
  JSBoolean forceConsent,
  JSString scope,
  JSFunction callback,
);

/// Llama a `requestGoogleDriveToken` definida en web/index.html (GIS).
/// Muestra un popup de consentimiento sin cerrar sesión.
///
/// [forceConsent] vuelve a mostrar la pantalla de permisos aunque el usuario
/// ya haya autorizado la app. Se usa cuando Drive responde que el token no
/// alcanza para lo que se pidió: quien autorizó con el permiso acotado de
/// antes tiene un token válido pero insuficiente, y pedir otro sin forzar el
/// consentimiento devuelve exactamente el mismo scope.
/// [scope] permite pedir un ámbito distinto al habitual. Se usa para probar
/// `drive.file` sin cambiar el de toda la app.
Future<String?> requestDriveTokenPlatform(
  String clientId, {
  bool forceConsent = false,
  String scope = '',
}) async {
  final completer = Completer<String?>();

  try {
    final callback = ((JSString? token) {
      final t = token?.toDart ?? '';
      if (!completer.isCompleted) {
        completer.complete(t.isNotEmpty ? t : null);
      }
    }).toJS;

    _requestGoogleDriveToken(
      clientId.toJS,
      forceConsent.toJS,
      scope.toJS,
      callback,
    );
  } catch (e) {
    if (!completer.isCompleted) completer.complete(null);
  }

  return completer.future;
}
