// Stub para plataformas no-web (móvil/desktop)
import 'package:google_sign_in/google_sign_in.dart';

/// Permiso completo de Drive.
///
/// Era `drive.file`, que solo da acceso a los archivos que la propia app creó:
/// un archivo que el usuario sube a Drive desde el computador era invisible
/// para Bitácora, y los borrados hechos fuera de la app no se podían detectar
/// de forma confiable. Google no ofrece un permiso acotado a una carpeta
/// (existía en la API v2, no en la v3), así que para eso hace falta el permiso
/// amplio. **La app se restringe por código al árbol de la carpeta Bitácora**;
/// esa restricción ya no la impone Google.
const _driveScope = 'https://www.googleapis.com/auth/drive';

/// Pide un access token de Drive sin mostrar ningún diálogo, reutilizando la
/// sesión nativa de Google ya autorizada (el usuario dio el permiso una vez
/// al iniciar sesión). Si no hay una sesión previa o falla (p. ej. sin red,
/// o el usuario revocó el acceso), devuelve null y quien llama decide el
/// fallback.
///
/// [forceConsent] descarta la sesión nativa y abre el diálogo de Google. Hace
/// falta para quien autorizó cuando la app pedía el permiso acotado:
/// `signInSilently()` reutiliza ese consentimiento y devuelve un token con el
/// scope viejo una y otra vez, que Drive rechaza con 403.
Future<String?> requestDriveTokenPlatform(
  String clientId, {
  bool forceConsent = false,
}) async {
  try {
    final googleSignIn = GoogleSignIn(
      serverClientId: clientId,
      scopes: ['email', 'profile', _driveScope],
    );

    if (forceConsent) {
      try {
        await googleSignIn.signOut();
      } catch (_) {
        // Sin sesión previa que limpiar: seguir igual al signIn interactivo.
      }
      final account = await googleSignIn.signIn();
      if (account == null) return null;
      final auth = await account.authentication;
      return auth.accessToken;
    }

    final account = await googleSignIn.signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  } catch (_) {
    return null;
  }
}
