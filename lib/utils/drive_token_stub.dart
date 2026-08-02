// Stub para plataformas no-web (móvil/desktop)
import 'package:google_sign_in/google_sign_in.dart';

const _driveScope = 'https://www.googleapis.com/auth/drive.file';

/// Pide un access token de Drive sin mostrar ningún diálogo, reutilizando la
/// sesión nativa de Google ya autorizada (el usuario dio el permiso una vez
/// al iniciar sesión). Si no hay una sesión previa o falla (p. ej. sin red,
/// o el usuario revocó el acceso), devuelve null y quien llama decide el
/// fallback.
Future<String?> requestDriveTokenPlatform(String clientId) async {
  try {
    final googleSignIn = GoogleSignIn(
      serverClientId: clientId,
      scopes: ['email', 'profile', _driveScope],
    );
    final account = await googleSignIn.signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  } catch (_) {
    return null;
  }
}
