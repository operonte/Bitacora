// Stub para plataformas no-web (móvil/desktop)
import 'package:google_sign_in/google_sign_in.dart';

/// Permiso acotado de Drive: solo ve lo que la propia app crea.
///
/// Antes era el permiso completo, que además de ver todo el Drive disparaba
/// la pantalla de "Google no ha verificado esta aplicación" para cualquier
/// usuario y ponía un tope de 100 cuentas hasta pasar una auditoría paga
/// (CASA). Se volvió a `drive.file` a propósito: el costo es que un archivo
/// que alguien suba a Drive desde fuera de la app queda invisible para
/// Bitácora, aceptable para una app pensada para gente que solo usa el botón
/// de subir de adentro.
const _driveScope = 'https://www.googleapis.com/auth/drive.file';

/// Pide un access token de Drive sin mostrar ningún diálogo, reutilizando la
/// sesión nativa de Google ya autorizada (el usuario dio el permiso una vez
/// al iniciar sesión). Si no hay una sesión previa o falla (p. ej. sin red,
/// o el usuario revocó el acceso), devuelve null y quien llama decide el
/// fallback.
///
/// [forceConsent] descarta la sesión nativa y abre el diálogo de Google. Hace
/// falta para quien autorizó con un scope viejo: `signInSilently()` reutiliza
/// ese consentimiento y devuelve un token que Drive rechaza con 403.
/// [scope] permite pedir un ámbito distinto al habitual. Nada lo usa hoy;
/// queda para que las dos implementaciones (esta y la de web) tengan la
/// misma firma.
Future<String?> requestDriveTokenPlatform(
  String clientId, {
  bool forceConsent = false,
  String scope = '',
}) async {
  try {
    final googleSignIn = GoogleSignIn(
      serverClientId: clientId,
      scopes: [
        'email',
        'profile',
        if (scope.isNotEmpty) scope else _driveScope,
      ],
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
