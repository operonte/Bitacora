// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:js_interop';

/// Declaración del tipo de función callback para JS
extension type _DriveTokenCallback._(JSFunction _) implements JSFunction {
  external factory _DriveTokenCallback(JSString? token);
}

@JS('requestGoogleDriveToken')
external void _requestGoogleDriveToken(JSString clientId, JSFunction callback);

/// Llama a `requestGoogleDriveToken` definida en web/index.html (GIS).
/// Muestra un popup de consentimiento sin cerrar sesión.
Future<String?> requestDriveTokenPlatform(String clientId) async {
  final completer = Completer<String?>();

  try {
    final callback = ((JSString? token) {
      final t = token?.toDart ?? '';
      if (!completer.isCompleted) {
        completer.complete(t.isNotEmpty ? t : null);
      }
    }).toJS;

    _requestGoogleDriveToken(clientId.toJS, callback);
  } catch (e) {
    if (!completer.isCompleted) completer.complete(null);
  }

  return completer.future;
}
